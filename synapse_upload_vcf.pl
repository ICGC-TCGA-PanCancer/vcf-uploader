#!/usr/bin/env perl

use warnings;
use strict;

use feature qw(say);
use autodie;
use Carp::Always;
use Carp qw( croak );

use Getopt::Long;
use XML::DOM;
use XML::XPath;
use XML::XPath::XMLParser;
use JSON;

use Data::Dumper;

my $milliseconds_in_an_hour = 3600000;

#############################################################################################
# DESCRIPTION                                                                               #
#############################################################################################
# 
#############################################################################################



# Edit as required!
use constant cooldown     => 60;
use constant retries      => 30;
use constant md5_sleep    => 240;

use constant pem_file     => 'gnostest.pem';     #
use constant output_dir   => 'test_output_dir';  # configurable as command line arg
use constant xml_dir      => 'xml';              #


#############
# VARIABLES #
#############

my $parser        = new XML::DOM::Parser;
my $output_dir    = output_dir;
my $xml_dir       = xml_dir;
my $pem_file      = pem_file;
my $cooldown      = cooldown;
my $retries       = retries;
my $md5_sleep     = md5_sleep;

my ($metadata_url,$force_copy,$help);
GetOptions(
    "metadata-urls=s"  => \$metadata_url,
    "force-copy"       => \$force_copy,
    "output-dir=s"     => \$output_dir,
    "xml-dir=s"        => \$xml_dir,
    "pem-file=s"       => \$pem_file,
    "help"             => \$help
    );

die << 'END' if $help;
Usage: synapse_upload_vcf.pl[--metadata-url url] 
                            [--force-copy] 
                            [--output-dir dir]
                            [--xml-dir]
                            [--pem-file file.pem]
                            [--help]
END
;
 

$output_dir = "vcf/$output_dir";
run("mkdir -p $output_dir");
run("mkdir -p $xml_dir");

my $link_method = ($force_copy)? 'rsync -rauv': 'ln -s';
my $pwd = `pwd`;
chomp $pwd;

# If we don't have a url, get the list by elastic search
my @metadata_urls;
unless ($metadata_url) {
    say "Getting metadata URLs by elastic search...";
    @metadata_urls = `./get_donors_by_elastic_search.pl`;
    chomp @metadata_urls;
}
else {
    @metadata_urls = ($metadata_url);
}

# First, read in the metadata and save the workflow
# version
my %variant_workflow_version;
my %to_be_processed;
for my $url (@metadata_urls) {
    say "metadata URL=$url";
    my $metad = download_metadata($url);

    # save workflow version 
    workflow_version($metad);
   
    my ($analysis_id) = $url =~ m!/([^/]+)$!;
    $to_be_processed{$analysis_id} = $metad;
}

# Then, do the upload only for the most recent version
while (my ($analysis_id,$metad) = each %to_be_processed) {
    next unless newest_workflow_version($metad);
    
    my $json  = generate_output_json($metad);
    say $json;

    open JFILE, ">$output_dir/$analysis_id.json";
    print JFILE $json;
    close JFILE;

    say "JSON saved as $output_dir/$analysis_id.json";
}

# Check to see if this donor has VCF results from a more recent
# version of the workflow.
sub newest_workflow_version {
    return workflow_version(@_);
}
sub workflow_version {
    my $metad = shift;
    my ($data) = values %$metad;
    my ($donor_id) = keys %{$data->{analysis_attr}->{submitter_donor_id}};
    my $center     = $data->{center_name};
    my ($workflow) =  keys %{$data->{analysis_attr}->{variant_workflow_name}};
    my ($version)  =  keys %{$data->{analysis_attr}->{variant_workflow_version}};
    
    # unique donor ID
    $donor_id = join('-',$center,$donor_id);
    
    # check if our workflow version is more recent
    return is_more_recent($donor_id,$workflow,$version);
}

sub is_more_recent {
    my $donor   = shift;
    my $name    = shift;
    my $version = shift;
    my ($primary,$secondary,$tertiary) = split('\.',$version);

    my $wf_version = $variant_workflow_version{$donor}{$name};
    if (not defined $wf_version) {
	$variant_workflow_version{$donor}{$name} = [$primary,$secondary,$tertiary];
	return 1;
    }
    elsif (
	$primary   > $wf_version->[0]
	||
	($secondary > $wf_version->[1] && $primary == $wf_version->[0])
	||
	($tertiary  > $wf_version->[2] && $primary == $wf_version->[0] && $secondary == $wf_version->[1])
	) {
	$variant_workflow_version{$donor}{$name} = [$primary,$secondary,$tertiary];
	return 1;
    }
    elsif (
        $primary   == $wf_version->[0]
        &&
        $secondary == $wf_version->[1]
        &&
        $tertiary  == $wf_version->[2]
	) {
	$variant_workflow_version{$donor}{$name} = [$primary,$secondary,$tertiary];
	return 1;
    }
    return 0;
}

# This method gets the information about the BWA alignment outputs/VCF inputs
sub get_sample_data {
    my $metad = shift;
    my $json  = shift;
    my $anno  = $json->{annotations};
    my ($input_json_string) = keys %{$metad->{variant_pipeline_input_info}};
    my $input_data = decode_json $input_json_string;

    my ($inputs)     = values %$input_data; 

    my ($tumor_sid, $normal_sid, @urls, $tumor_aid, $normal_aid);
    for my $specimen (@$inputs) {
	my $type = $specimen->{attributes}->{dcc_specimen_type};
	my $sample_id = $specimen->{specimen};
	my $analysis_id =  $specimen->{attributes}->{analysis_id};
	my $is_tumor = $type =~ /tumou?r|xenograft|cell line/i;
	if ($is_tumor) {
	    $tumor_sid = $tumor_sid ? "$tumor_sid,$sample_id"   : $sample_id;
	    $tumor_aid = $tumor_aid ? "$tumor_aid,$analysis_id" : $analysis_id;
	}
	else {
	    $normal_sid = $normal_sid ? "$normal_sid,$sample_id"   : $sample_id;
	    $normal_aid = $normal_aid ? "$normal_aid,$analysis_id" : $analysis_id;
	}
	
	push @urls, $specimen->{attributes}->{analysis_url};
    }

    $anno->{sample_id_normal}  = $normal_sid;
    $anno->{analysis_id_normal} = $normal_aid;
    $anno->{sample_id_tumor}   = $tumor_sid;
    $anno->{analysis_id_tumor} = $tumor_aid;
    $json->{used_urls} = \@urls;
}


# We will neeed to grab the files from GNOS assuming synpase upload is
# not concurrent with GNOS upload
sub download_vcf_files {
    my $metad = shift;
    my $url = shift;
    my @files = @_;

    say "This is where I will be downloading files from GNOS";
    chdir $output_dir or die $!;
    for my $file (@files) {
	my $download_url = $metad->{$url}->{download_url};
	my $command = "gtdownload -c $pem_file";
	# and add the logic to download
#                  .addArgument("--command 'gtdownload -c " + pemFile )
#                  .addArgument("-v " + gnosServer + "/cghub/data/analysis/download/" + analysisId + "'")
#                  .addArgument("--file " + analysisId + "/" + bamFile)
#                  .addArgument("--retries 10 --sleep-min 1 --timeout-min 60");	
    }

    chdir $pwd or die $!;
}

sub get_files {
    my $metad = shift;
    my $url   = shift;
    my $file_data = $metad->{$url}->{file};
    my @file_data = map {[$_->{filename},$_->{checksum}]} @$file_data;
    download_vcf_files($metad,$url,@file_data);
    return @file_data;
}

sub get_file_names {
    my $metad = shift;
    my $url   = shift;
    my @data  = get_files($metad,$url);
    my @names = map {$_->[0]} @data;
    return [map{"$output_dir/$_"} @names];
}

sub generate_output_json {
    my ($metad) = @_;
    my $data = {};

    foreach my $url ( keys %{$metad} ) {
	$data->{files} = get_file_names($metad,$url);

	my $atts = $metad->{$url}->{analysis_attr};
	my $anno = $data->{annotations} = {};
	
	# top-level annotations
        $anno->{center_name}     = $metad->{$url}->{center_name};
        $anno->{reference_build} =  $metad->{$url}->{reference_build};

	# get original sample information
	get_sample_data($atts,$data);

	# from the attributes hash
	($anno->{donor_id})                   = keys %{$atts->{submitter_donor_id}};
	($anno->{study})                      = keys %{$atts->{STUDY}};
	($anno->{alignment_workflow_name})    = keys %{$atts->{alignment_workflow_name}};
	($anno->{alignment_workflow_version}) = keys %{$atts->{alignment_workflow_version }};
	($anno->{sequence_source})            = keys %{$atts->{sequence_source}};
	($anno->{workflow_url})               = keys %{$atts->{variant_workflow_bundle_url}};
	($anno->{workflow_src_url})           = keys %{$atts->{variant_workflow_source_url}};
	($anno->{project_code})               = keys %{$atts->{dcc_project_code}};
	($anno->{workflow_version})           = keys %{$atts->{variant_workflow_version}};
	($anno->{workflow_name})              = keys %{$atts->{variant_workflow_name}};
        $anno->{original_analysis_id}         = join(',',sort keys %{$atts->{original_analysis_id}});

	# harder to get attributes
	$anno->{call_type} = (grep {/\.somatic\./} @{$data->{files}}) ? 'somatic' : 'germline';

	my $wiki = $data->{wiki_content} = {};
	$wiki->{title}                = $metad->{$url}->{title};
	$wiki->{description}          = $metad->{$url}->{description};

	my $exe_urls = $data->{executed_urls} = [];
	push @$exe_urls, keys %{$atts->{variant_workflow_bundle_url}};
	push @$exe_urls, keys %{$atts->{alignment_workflow_bundle_url}};
    }


    my $json = JSON->new->pretty->encode( $data);
    #say $json;
    return $json;
}

sub download_metadata {
    my $url = shift;
    my $metad = {};

    my ($id) = $url =~ m!/([^/]+)$!;
    my $xml_path = download_url( $url, "$xml_dir/data_$id.xml" );
    $metad->{$url} = parse_metadata($xml_path);

    return $metad;
}

sub parse_metadata {
    my ($xml_path) = @_;
    my $doc        = $parser->parsefile($xml_path);
    my $m          = {};

    $m->{'analysis_id'}  = getVal( $doc, 'analysis_id' );
    $m->{'center_name'}  = getVal( $doc, 'center_name' );
    $m->{'title'}        = getVal( $doc, 'TITLE');
    $m->{'description'}  = getVal( $doc, 'DESCRIPTION');
    $m->{'platform'}     = getVal( $doc, 'platform');
    $m->{'download_url'} = getVal( $doc, 'analysis_data_uri');
    $m->{'reference_build'} = getTagAttVal( $doc, 'STANDARD', 'short_name' );
    $m->{'analysis_center'} = getTagAttVal( $doc, 'ANALYSIS', 'analysis_center' );

    push @{ $m->{'file'} },
      getValsMulti( $doc, 'FILE', "checksum,filename,filetype" );

    $m->{'analysis_attr'} = getAttrs($doc);
    return ($m);
}

sub getBlock {
    my ( $xml_file, $xpath ) = @_;

    my $block = "";
    ## use XPath parser instead of using REGEX to extract desired XML fragment, to fix issue: https://jira.oicr.on.ca/browse/PANCANCER-42
    my $xp = XML::XPath->new( filename => $xml_file )
      or die "Can't open file $xml_file\n";

    my $nodeset = $xp->find($xpath);
    foreach my $node ( $nodeset->get_nodelist ) {
        $block .= XML::XPath::XMLParser::as_string($node) . "\n";
    }

    return $block;
}

sub download_url {
    my ( $url, $path ) = @_;

    my $response = run("wget -q -O $path $url");
    if ($response) {
        $ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 0;
        $response = run("lwp-download $url $path");
        if ($response) {
            say "ERROR DOWNLOADING: $url";
            exit 1;
        }
    }
    return $path;
}

sub getVal {
    my ( $node, $key ) = @_;

    if ( $node ) {
        if ( defined( $node->getElementsByTagName($key) ) ) {
            if ( defined( $node->getElementsByTagName($key)->item(0) ) ) {
                if (
                    defined(
                        $node->getElementsByTagName($key)->item(0)
                          ->getFirstChild
                    )
                  )
                {
                    if (
                        defined(
                            $node->getElementsByTagName($key)->item(0)
                              ->getFirstChild->getNodeValue
                        )
                      )
                    {
                        return ( $node->getElementsByTagName($key)->item(0)
                              ->getFirstChild->getNodeValue );
                    }
                }
            }
        }
    }
    return (undef);
}

sub getAttrs {
    my ($node) = @_;

    my $r     = {};
    my $nodes = $node->getElementsByTagName('ANALYSIS_ATTRIBUTE');
    for ( my $i = 0 ; $i < $nodes->getLength ; $i++ ) {
        my $anode = $nodes->item($i);
        my $tag   = getVal( $anode, 'TAG' );
        my $val   = getVal( $anode, 'VALUE' );
        $r->{$tag}{$val} = 1;
    }

    return $r;
}

sub getTagAttVal {
    my $doc = shift;
    my $tag = shift;
    my $att = shift;
    my $nodes = $doc->getElementsByTagName($tag);
    my $n = $nodes->getLength;

    for (my $i = 0; $i < $n; $i++)
    {
	my $node = $nodes->item($i);
	my $val = $node->getAttributeNode($att);
	return $val->getValue;
    }
}

sub getValsWorking {
    my ( $node, $key, $tag ) = @_;

    my @result;
    my $nodes = $node->getElementsByTagName($key);
    for ( my $i = 0 ; $i < $nodes->getLength ; $i++ ) {
        my $anode = $nodes->item($i);
        my $tag   = $anode->getAttribute($tag);
        push @result, $tag;
    }

    return @result;
}

sub getValsMulti {
    my ( $node, $key, $tags_str ) = @_;
    my @result;
    my @tags = split /,/, $tags_str;
    my $nodes = $node->getElementsByTagName($key);
    for ( my $i = 0 ; $i < $nodes->getLength ; $i++ ) {
        my $data = {};
        foreach my $tag (@tags) {
            my $anode = $nodes->item($i);
            my $value = $anode->getAttribute($tag);
            if ( defined($value) && $value ne '' ) { $data->{$tag} = $value; }
        }
        push @result, $data;
    }
    return (@result);
}

sub run {
    my ( $cmd, $do_die ) = @_;

    say "CMD: $cmd";
    my $result = system($cmd);
    if ( $do_die && $result ) {
        croak "ERROR: CMD '$cmd' returned non-zero status";
    }

    return ($result);
}

1;
