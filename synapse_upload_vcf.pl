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

use XML::LibXML;
use Time::Piece;

use GNOS::Upload;
use Data::Dumper;

my $milliseconds_in_an_hour = 3600000;

#############################################################################################
# DESCRIPTION                                                                               #
#############################################################################################
# 
#############################################################################################


#############
# VARIABLES #
#############

# seconds to wait for a retry
my $cooldown = 60;
# 30 retries at 60 seconds each is 30 hours
my $retries = 30;
# retries for md5sum, 4 hours
my $md5_sleep = 240;

my $parser        = new XML::DOM::Parser;
my $output_dir    = "test_output_dir";
my $key           = "gnostest.pem";
my $upload_url    = "";
my $test          = 0;

my ($metadata_url,$force_copy);
GetOptions(
    "metadata-urls=s"  => \$metadata_url,
    "force-copy"       => \$force_copy,
    "output_dir=s"     => \$output_dir
    );

$metadata_url or die "Usage: synapse_upload_vcf.pl --metadata-url url [--force-copy]\n"; 

##############
# MAIN STEPS #
##############

# setup output dir
say "SETTING UP OUTPUT DIR";

$output_dir = "vcf/$output_dir";
run("mkdir -p $output_dir");
my $final_touch_file = $output_dir."upload_complete.txt";


# parse metadata
my @metadata_urls = split /,/, $metadata_url;

say 'COPYING FILES TO OUTPUT DIR';

my $link_method = ($force_copy)? 'rsync -rauv': 'ln -s';
my $pwd = `pwd`;
chomp $pwd;

for my $url (@metadata_urls) {
    my $metad = download_metadata($metadata_url);
    my $json  = generate_output_json($metad);
    my ($analysis_id) = $url =~ m!/([^/]+)$!;
    open JFILE, ">$output_dir/$analysis_id.json";
    print JFILE $json;
    close JFILE;
    say "JSON saved as $output_dir/$analysis_id.json";
}


###############
# SUBROUTINES #
###############

# "used_urls": ["https://gtrepo-dkfz.annailabs.com/cghub/data/analysis/download/.../comma_list_of_aligned_bam_files",
#                "ftp://ftp.1000genomes.ebi.ac.uk/vol1/ftp/technical/reference/phase2_reference_assembly_sequence/hs37d5.fa.gz/.../or_other_correct_url"],
# "executed_urls":  ["https://github.com/SeqWare/public-workflows/tree/vcf-1.1.0/workflow-DKFZ-bundle",
#                    "https://s3.amazonaws.com/oicr.workflow.bundles/released-bundles/Workflow_Bundle_BWA_2.6.0_SeqWare_1.0.15.zip/.../Point/to_Correct/URL"],

sub get_sample_ids {
    my $metad = shift;
    my ($out_info) = keys %{$metad->{variant_pipeline_output_info}};
    my @sample_ids = $out_info =~ /"submitter_sample_id":"([^"]+)"/g;
    return \@sample_ids;
}


sub generate_output_json {
    my ($metad) = @_;
    my $data = {};

    foreach my $url ( keys %{$metad} ) {
	my @files = map {"$output_dir/$_"} 
                    sort 
		    map {$_->{filename}} @{$metad->{$url}->{file}};
	
	$data->{files} = \@files;

	my $atts = $metad->{$url}->{analysis_attr};
	my $anno = $data->{annotations} = {};
	
	# top-level annotations
        $anno->{center_name}     = $metad->{$url}->{center_name};
        $anno->{sample_id}       = get_sample_ids($atts);
        $anno->{reference_build} =  $metad->{$url}->{reference_build};

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
        $anno->{original_analysis_id}         = [keys %{$atts->{original_analysis_id}}];

	# harder to get attributes
	$anno->{call_type} = (grep {/\.somatic\./} @files) ? 'somatic' : 'germline';
	$anno->{sample_id} = get_sample_ids($atts);

	my $wiki = $data->{wiki_content} = {};
	$wiki->{title}                = $metad->{$url}->{title};
	$wiki->{description}          = $metad->{$url}->{description};

	my $exe_urls = $data->{executed_urls} = [];
	push @$exe_urls, keys %{$atts->{variant_workflow_bundle_url}};
	push @$exe_urls, keys %{$atts->{alignment_workflow_bundle_url}};

	my $used_urls = $data->{used_urls} = [];
	push @$used_urls, "I am not sure what to to with this";

    }

    my $json = JSON->new->pretty->encode( $data);
    say $json;
    return $json;
}

sub download_metadata {
    my ($urls_str) = @_;
    my $metad = {};
    run("mkdir -p xml2");
    my @urls = split /,/, $urls_str;
    my $i = 0;
    foreach my $url (@urls) {
        $i++;
        my $xml_path = download_url( $url, "xml2/data_$i.xml" );
        $metad->{$url} = parse_metadata($xml_path);
    }
    return ($metad);
}

sub parse_metadata {
    my ($xml_path) = @_;
    my $doc        = $parser->parsefile($xml_path);
    my $m          = {};

    $m->{'analysis_id'} = getVal( $doc, 'analysis_id' );
    $m->{'center_name'} = getVal( $doc, 'center_name' );
    $m->{'analysis_center'} = getTagAttVal( $doc, 'ANALYSIS', 'analysis_center' );
    $m->{'title'}       = getVal( $doc, 'TITLE');
    $m->{'description'} = getVal( $doc, 'DESCRIPTION');
    $m->{'reference_build'} = getTagAttVal( $doc, 'STANDARD', 'short_name' );
    $m->{'platform'} = getVal( $doc, 'platform');

    push @{ $m->{'study_ref'} },
      getValsMulti( $doc, 'STUDY_REF', "refcenter,refname" );
    push @{ $m->{'run'} },
      getValsMulti( $doc, 'RUN', "data_block_name,read_group_label,refname" );
#    push @{ $m->{'target'} },
#      getValsMulti( $doc, 'TARGET', "refcenter,refname" );
    push @{ $m->{'file'} },
      getValsMulti( $doc, 'FILE', "checksum,filename,filetype" );

    $m->{'analysis_attr'} = getAttrs($doc);
#    $m->{'experiment'}    = getBlock( $xml_path,
#        "/ResultSet/Result/experiment_xml/EXPERIMENT_SET/EXPERIMENT" );
#    $m->{'run_block'} =
#      getBlock( $xml_path, "/ResultSet/Result/run_xml/RUN_SET/RUN" );
    
#    say Dumper $m;
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

0;
