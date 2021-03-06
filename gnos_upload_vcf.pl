#!/usr/bin/env perl

# TODO: Adam, turn this back on after you've address the source of the warnings. It makes it impossible to see the output of the program otherwise
# use warnings;
use strict;

use feature qw(say);
use autodie;
use IPC::System::Simple qw(system);

use Carp::Always;
use Carp qw( croak );

use Getopt::Long;
use XML::DOM;
use XML::XPath;
use XML::XPath::XMLParser;
use JSON;
use Data::UUID;
use XML::LibXML;
use Time::Piece;

use GNOS::Upload;
use Data::Dumper;

my $milliseconds_in_an_hour = 3600000;

#############################################################################################
# DESCRIPTION                                                                               #
#############################################################################################
# This tool takes metadata URLs and VCF path(s). It then downloads metadata,                #
# parses it, generates submission files, and then performs the uploads.                     #
# See https://github.com/SeqWare/public-workflows/blob/develop/vcf-uploader/README.md       #
# Also see https://wiki.oicr.on.ca/display/PANCANCER/PCAWG+VCF+Submission+SOP+-+v1.0        #
#############################################################################################

#############
# VARIABLES #
#############

# min to wait for a retry
my $cooldown = 1;
# 3 retries at 20 min each is 1 hour
my $retries = 3;
# retries timeout in min
my $timeout_min = 20;
my $k_timeout_min = 60;

my $vcfs = "";
my $md5_file = "";
my $vcfs_idx = "";
my $md5_idx_file = "";
my $tarballs = "";
my $md5_tarball_file = "";

# TODO: Sheldon, we will need parameters to the program for the various hard-coded bits below
my $parser        = new XML::DOM::Parser;
my $output_dir    = "test_output_dir";
my $key           = "gnostest.pem";
my $upload_url    = "";
my $test          = 0;
my $skip_validate = 0;
my $skip_upload   = 0;

# hardcoded
my $seqware_version  = "1.1.0-alpha.4";
my $workflow_version = "1.0.0";
my $workflow_name    = "Workflow_Bundle_Test_Cancer_Variant_Analysis";

# hardcoded
my $workflow_src_url =
"https://github.com/testproject/workflow-test-cancer/tree/$workflow_version/workflow-broad-cancer";
my $workflow_url =
"https://s3.amazonaws.com/oicr.workflow.bundles/released-bundles/Workflow_Bundle_Test_Cancer_Variant_Analysis_"
  . $workflow_version
  . "_SeqWare_$seqware_version.zip";
my $changelog_url = "CHANGELOG.md";
my $force_copy      = 0;
my $study_ref_name  = "icgc_pancancer_vcf";
my $analysis_center = "OICR";
my $center_override = "";
my $refcenter_override = "";
my $metadata_url       = "";
my $metadata_paths     = "";
my $make_runxml        = 0;
my $make_expxml        = 0;
my $description_file   = "";
my $pipeline_json_file = "";
my $qc_json_file       = "";
my $timing_json_file   = "";
my $upload_archive     = "";
my $uuid               = "";
my $vm_instance_type   = "unknown";
my $vm_instance_cores  = "unknown";
my $vm_instance_mem_gb = "unknown";
my $vm_location_code   = "unknown";
my $help = 0;
my $workflow_file_subset = "";
my $related_file_subset_uuids = "";
my $gto_only = 0;

my $bams = "";
my $bam_md5sum_files = "";
my $bam_bais = "";
my $bam_bais_md5sum_files = "";

# TODO: check the argument counts here
if ( scalar(@ARGV) == 0 ) {
    die get_usage();
}

GetOptions(
    "metadata-urls=s"            => \$metadata_url,
    "metadata-paths=s"           => \$metadata_paths,
    "vcfs=s"                     => \$vcfs,
    "vcf-md5sum-files=s"         => \$md5_file,
    "vcf-idxs=s"                 => \$vcfs_idx,
    "vcf-idx-md5sum-files=s"     => \$md5_idx_file,
    "tarballs=s"                 => \$tarballs,
    "tarball-md5sum-files=s"     => \$md5_tarball_file,
    "outdir=s"                   => \$output_dir,
    "key=s"                      => \$key,
    "upload-url=s"               => \$upload_url,
    "workflow-src-url=s"         => \$workflow_src_url,
    "workflow-url=s"             => \$workflow_url,
    "workflow-name=s"            => \$workflow_name,
    "workflow-version=s"         => \$workflow_version,
    "seqware-version=s"          => \$seqware_version,
    "description-file=s"         => \$description_file,
    "study-refname-override=s"   => \$study_ref_name,
    "center-override=s"          => \$center_override,
    "ref-center-override=s"      => \$refcenter_override,
    "analysis-center-override=s" => \$analysis_center,
    "pipeline-json=s"            => \$pipeline_json_file,
    "qc-metrics-json=s"          => \$qc_json_file,
    "timing-metrics-json=s"      => \$timing_json_file,
    "make-runxml"                => \$make_runxml,
    "make-expxml"                => \$make_expxml,
    "force-copy"                 => \$force_copy,
    "skip-validate"              => \$skip_validate,
    "skip-upload"                => \$skip_upload,
    "test"                       => \$test,
    "upload-archive=s"           => \$upload_archive,
    "vm-instance-type=s"         => \$vm_instance_type,
    "vm-instance-cores=s"        => \$vm_instance_cores,
    "vm-instance-mem-gb=s"       => \$vm_instance_mem_gb,
    "vm-location-code=s"         => \$vm_location_code,
    "uuid=s"                     => \$uuid,
    "timeout-min=i"              => \$timeout_min,
    "k-timeout-min=i"            => \$k_timeout_min,
    "retries=i"                  => \$retries,
    "help"                       => \$help,
    "workflow-file-subset=s"     => \$workflow_file_subset,
    "related-file-subset-uuids=s" => \$related_file_subset_uuids,
    "gto-only"                   => \$gto_only,
    "bams:s"                       => \$bams,
    "bam-md5sum-files:s"           => \$bam_md5sum_files,
    "bam-bais:s"                   => \$bam_bais,
    "bam_bai-md5sum-files:s"           => \$bam_bais_md5sum_files
);

# if --help
if ($help) {
  die get_usage();
}

##############
# MAIN STEPS #
##############

# setup output dir
say "SETTING UP OUTPUT DIR";

# creating a new UUID if not specified
my $ug = Data::UUID->new;
if ($uuid eq "") {
  $uuid = lc($ug->create_str());
}

# output dir setup
$output_dir = "vcf/$output_dir";
run("mkdir -p $output_dir/$uuid");
$output_dir = "$output_dir/$uuid/";
my $final_touch_file = $output_dir."upload_complete.txt";

# parse values
my @vcf_arr          = split /,/, $vcfs;
my @bam_arr          = split /,/, $bams;
my @md5_file_arr     = split /,/, $md5_file;
my @bam_md5_file_arr = split /,/, $bam_md5sum_files;
my @vcfs_idx_arr     = split /,/, $vcfs_idx;
my @bams_bai_arr     = split /,/, $bam_bais;
my @md5_idx_file_arr = split /,/, $md5_idx_file;
my @bam_bai_md5_arr  = split /,/, $bam_bais_md5sum_files;
my @vcf_checksums;
my @bam_checksums;
my @bai_checksums;
my @idx_checksums;
my @tarball_checksums;
my @tarball_arr          = split /,/, $tarballs;
my @md5_tarball_file_arr = split /,/, $md5_tarball_file;

# TODO: Sheldon, we'll need more validation here, check each VCF file for headers etc. See https://wiki.oicr.on.ca/display/PANCANCER/PCAWG+VCF+Submission+SOP+-+v1.0
say 'VALIDATING PARAMS';
die "Must specify at least one VCF or one Tarball or BAM!\n"     if ( scalar(@tarball_arr) == 0 && scalar(@vcf_arr) == 0 && scalar(@bam_arr) == 0);
die "VCF and VCF md5sum file count don't match!\n"        if ( scalar(@vcf_arr) != scalar(@md5_file_arr) );
die "VCF and VCF index count don't match!\n"              if ( scalar(@vcf_arr) != scalar(@vcfs_idx_arr) );
die "VCF index and VCF index md5sum count don't match!\n" if ( scalar(@vcf_arr) != scalar(@md5_idx_file_arr) );
die "Tarball and Tarball md5sum count don't match!\n"     if ( scalar(@tarball_arr) != scalar(@md5_tarball_file_arr) );
die "Keyfile $key not found!\n"                           if (!-e $key);

# BAMs should be optional.
if (scalar (@bam_arr) >0 )
{
  die "BAM and BAM md5sum file counts don't match!\n" if ( scalar(@bam_arr) != scalar(@bam_md5_file_arr) );
  die "BAM and BAM index file counts don't match!\n" if ( scalar(@bam_arr) != scalar(@bams_bai_arr) );
  die "BAM index and BAM index md5sum file counts don't match!\n" if ( scalar(@bam_bai_md5_arr) != scalar(@bams_bai_arr) );
}

say 'COPYING FILES TO OUTPUT DIR';
my $link_method = ($force_copy)? 'rsync -rauv': 'ln -s';
my $pwd = `pwd`;
chomp $pwd;

# loop for each VCF file
for ( my $i = 0 ; $i < scalar(@vcf_arr) ; $i++ ) {
    my $vcf_check = `cat $md5_file_arr[$i]`;
    $vcf_check =~ s/^\s+|\s+$//g;
    say "CAT CODE! cat $md5_file_arr[$i]";
    my $idx_check = `cat $md5_idx_file_arr[$i]`;
    $idx_check =~ s/^\s+|\s+$//g;
    chomp $vcf_check;
    chomp $idx_check;
    push @vcf_checksums, $vcf_check;
    push @idx_checksums, $idx_check;

    my @files = ($vcf_arr[$i], $md5_file_arr[$i], $vcfs_idx_arr[$i], $md5_idx_file_arr[$i]);

    foreach my $file (@files) {
        my @t = split /\//, $file;
        my $root = $t[scalar(@t)-1];
        my $command = "$link_method `readlink -f $file` $output_dir/";
        print "ROOT: $root\n";
        if (!(-e "$output_dir/$root")) {
          run($command);
        }
    }
}
#Now do it for all BAM files
for ( my $i = 0 ; $i < scalar(@bam_arr) ; $i++ ) {
    my $bam_check = `cat $bam_md5_file_arr[$i]`;
    $bam_check =~ s/^\s+|\s+$//g;
    say "CAT CODE! cat $bam_md5_file_arr[$i]";
    my $bai_check = `cat $bam_bai_md5_arr[$i]`;
    $bai_check =~ s/^\s+|\s+$//g;
    chomp $bam_check;
    chomp $bai_check;
    push @bam_checksums, $bam_check;
    push @bai_checksums, $bai_check;

    my @files = ($bam_arr[$i], $bam_md5_file_arr[$i], $bams_bai_arr[$i], $bam_bai_md5_arr[$i]);

    foreach my $file (@files) {
        my @t = split /\//, $file;
        my $root = $t[scalar(@t)-1];
        my $command = "$link_method `readlink -f $file` $output_dir/";
        print "ROOT: $root\n";
        if (!(-e "$output_dir/$root")) {
          run($command);
        }
    }
}

# loop for each tarball
for ( my $i = 0 ; $i < scalar(@tarball_arr) ; $i++ ) {
    my $tarball_check = `cat $md5_tarball_file_arr[$i]`;
    chomp $tarball_check;
    $tarball_check =~ s/^\s+|\s+$//g;
    push @tarball_checksums, $tarball_check;
    my $tarball_file = $tarball_arr[$i];
    my @t = split /\//, $tarball_arr[$i];
    my $root = $t[scalar(@t)-1];
    my $command = "$link_method `readlink -f $tarball_file` $output_dir/";
    print "ROOT: $root\n";
    if (!(-e "$output_dir/$root")) {
      run($command);
    }
}

say 'DOWNLOADING METADATA FILES';
my $metad            = download_metadata($metadata_url, $metadata_paths);
my $input_json_hash  = generate_input_json($metad);
my $output_json_hash = generate_output_json($metad);

say 'GENERATING SUBMISSION';
my $sub_path = generate_submission( $metad, $input_json_hash, $output_json_hash );

say 'VALIDATING SUBMISSION';
die "The submission did not pass validation! Files are located at: $sub_path\n"
                                                       if ( validate_submission($sub_path) );

say 'UPLOADING SUBMISSION';
die "The upload of files did not work!  Files are located at: $sub_path\n"
                                                       if ( upload_submission($sub_path) );

###############
# SUBROUTINES #
###############

sub get_usage {
  return "USAGE: 'perl gnos_upload_vcf.pl
     --metadata-urls <URLs_for_specimen-level_aligned_BAM_input_comma_sep>
     --outdir <output_dir>
     --key <gnos.pem>
     --upload-url <gnos_server_url>
     # you must specify --vcfs, --vcf-md5sum-files, --vcf-idxs, and --vcf-idx-md5sum-files AND/OR --tarballs or --tarball-md5sum-files
     [--vcfs <sample-level_vcf_file_path_comma_sep_if_multiple>]
     [--vcf-md5sum-files <file_with_vcf_md5sum_comma_sep_same_order_as_vcfs>]
     [--vcf-idxs <sample-level_vcf_idx_file_path_comma_sep_if_multiple>]
     [--vcf-idx-md5sum-files <file_with_vcf_idx_md5sum_comma_sep_same_order_as_vcfs>]
     # and/or
     [--tarballs <tar.gz_non-vcf_files_comma_sep_if_multiple>]
     [--tarball-md5sum-files <file_with_tarball_md5sum_comma_sep_same_order_as_tarball>]
     # these are optional but highly recommended
     [--workflow-src-url <http://... the source repo>]
     [--workflow-url <http://... the packaged SeqWare Zip>]
     [--workflow-name <workflow_name>]
     [--workflow-version <workflow_version>]
     [--vm-instance-type <vmInstanceType>]
     [--vm-instance-cores <vmInstanceCores>]
     [--vm-instance-mem-gb <vmInstanceMemGb>]
     [--vm-location-code <vmLocationCode>]
     # these are optional but used to link two or more distinct GNOS uploads for a given workflow (typically a workflow does a single upload to GNOS at the end but some divide the upload into multiple GNOS submissions)
     [--workflow-file-subset <name_that_describes_this_subset_of_files_from_the_workflow_chosen_by_workflow_author>]
     [--related-file-subset-uuids <comma_delimited_list_of_GNOS_analysis_uuids_of_the_other_uploads_related_to_this_upload_used_when_a_workflow_performs_multiple_gnos_uploads_and_wants_to_related_them_explicitly>]
     # these are optional but required if using local file mode and not GNOS for metadata
     [--metadata-paths <local_paths_for_specimen-level_aligned_BAM_xml_comma_sep> ]
     # the rest are optional
     [--timeout-min <20>]
     [--retries <3>]
     [--k-timeout-min <60>]
     [--seqware-version <seqware_version_workflow_compiled_with>]
     [--description-file <file_path_for_description_txt>]
     [--study-refname-override <study_refname_override>]
     [--center-override <center_override>]
     [--ref-center-override <center_override>]
     [--analysis-center-override <analysis_center_override>]
     [--pipeline-json <pipeline_json_file>]
     [--qc-metrics-json <qc_metrics_json_file>]
     [--timing-metrics-json <timing_metrics_json_file>]
     [--make-runxml]
     [--make-expxml]
     [--force-copy]
     [--skip-validate]
     [--skip-upload]
     [--upload-archive <path_of_dir_to_copy_upload_to_and_make_tarball_uuid.tar.gz>]
     [--uuid <uuis_for_use_as_upload_analysis_id>]
     [--test]
     [--gto-only Pass the --gto-only flag to gtupload. GTO file will be generated, but no upload will occur. Do NOT use this flag with --skip-validate.]
     [--bams A list of bam files.]
     [--bam-md5sum-files A comma-separated list of md5sum files that correspond to the BAM files specified with --bam. This is mandatory if you use --bam.]
     [--bam-bais A comma-separated list of BAM Index files. This is mandatory if you use --bam.]
     [--bam_bai-md5sum-files A comma-separated list of md5sum files that correspond to the BAM Index files specified with --bam-bais. This is mandatory if you use --bam.]
     \n"
}

# this method generates a nice summary of the inputs to this workflow
# for inclusion in the analysis.xml
sub generate_input_json {
    my ($metad) = @_;
    my $d = {};

# cleanup and pull out the info I want, key off of specimen ID e.g. the SM field in the BAM header aka the aliquot_id in SRA XML
    foreach my $url ( keys %{$metad} ) {
        say "URL: $url";

        # pull back the target sample UUID
        my $target = $metad->{$url}{'target'}[0]{'refname'};

        # now fill in various info
        my $r = {};
        $r->{'specimen'}                   = $target;
        $r->{'attributes'}{'center_name'}  = $metad->{$url}{'center_name'};
        $r->{'attributes'}{'analysis_id'}  = $metad->{$url}{'analysis_id'};
        $r->{'attributes'}{'analysis_url'} = $url;
        $r->{'attributes'}{'study_ref'} = $metad->{$url}{'study_ref'}[0]{'refname'};
        $r->{'attributes'}{'dcc_project_code'} = join( ',',
            keys %{ $metad->{$url}{'analysis_attr'}{'dcc_project_code'} } );
        $r->{'attributes'}{'submitter_donor_id'} = join( ',',
            keys %{ $metad->{$url}{'analysis_attr'}{'submitter_donor_id'} } );
        $r->{'attributes'}{'submitter_sample_id'} = join( ',',
            keys %{ $metad->{$url}{'analysis_attr'}{'submitter_sample_id'} } );
        $r->{'attributes'}{'dcc_specimen_type'} = join( ',',
            keys %{ $metad->{$url}{'analysis_attr'}{'dcc_specimen_type'} } );
        $r->{'attributes'}{'use_cntl'} =
          join( ",", keys %{ $metad->{$url}{'analysis_attr'}{'use_cntl'} } );
        $r->{'attributes'}{'submitter_specimen_id'} = join( ',',
            keys %{ $metad->{$url}{'analysis_attr'}{'submitter_specimen_id'} }
        );

        push( @{ $d->{'workflow_inputs'} }, $r );
    }
    return $d;
}

# this method generates a nice summary of the outputs from this workflow
# for inclusion in the analysis.xml
sub generate_output_json {
    my ($metad) = @_;
    my $d = {};

# cleanup and pull out the info I want, key off of specimen ID e.g. the SM field in the BAM header aka the aliquot_id in SRA XML
    foreach my $url ( keys %{$metad} ) {
        say "URL: $url";

        # pull back the target sample UUID
        my $target = $metad->{$url}{'target'}[0]{'refname'};

        # now fill in various info
        my $r = {};
        $r->{'specimen'}                   = $target;
        $r->{'attributes'}{'center_name'}  = $metad->{$url}{'center_name'};
        $r->{'attributes'}{'analysis_id'}  = $metad->{$url}{'analysis_id'};
        $r->{'attributes'}{'analysis_url'} = $url;
        $r->{'attributes'}{'study_ref'} =
          $metad->{$url}{'study_ref'}[0]{'refname'};
        $r->{'attributes'}{'dcc_project_code'} = join( ',',
            keys %{ $metad->{$url}{'analysis_attr'}{'dcc_project_code'} } );
        $r->{'attributes'}{'submitter_donor_id'} = join( ',',
            keys %{ $metad->{$url}{'analysis_attr'}{'submitter_donor_id'} } );
        $r->{'attributes'}{'submitter_sample_id'} = join( ',',
            keys %{ $metad->{$url}{'analysis_attr'}{'submitter_sample_id'} } );
        $r->{'attributes'}{'dcc_specimen_type'} = join( ',',
            keys %{ $metad->{$url}{'analysis_attr'}{'dcc_specimen_type'} } );
        $r->{'attributes'}{'use_cntl'} =
          join( ",", keys %{ $metad->{$url}{'analysis_attr'}{'use_cntl'} } );
        $r->{'attributes'}{'submitter_specimen_id'} = join( ',',
            keys %{ $metad->{$url}{'analysis_attr'}{'submitter_specimen_id'} }
        );

        # now files
        process_files( $r, $target, \@vcf_arr );
        process_files( $r, $target, \@vcfs_idx_arr );
        process_files( $r, $target, \@tarball_arr );
        process_files( $r, $target, \@bam_arr );
        process_files( $r, $target, \@bams_bai_arr );

        push( @{ $d->{'workflow_outputs'} }, $r );
    }
    return $d;
}

# parse info from the file name
# TODO: Sheldon, want better validation here... something that barfs if extra files are provided that don't conform to the naming standard. See https://wiki.oicr.on.ca/display/PANCANCER/PCAWG+VCF+Submission+SOP+-+v1.0
sub process_files {
    my ( $r, $target, $arr ) = @_;

    foreach my $file ( @{$arr} ) {
        if ( $file =~ /$target\.([^\.]+)_([^\.]+)\.(\d+)\.([^\.]+)\./ ) {
            $r->{'files'}{$file}{'specimen'}      = $target;
            $r->{'files'}{$file}{'workflow_name'} = $1;
            my $workflow_version = $2;
            $r->{'files'}{$file}{'date'}      = $3;
            $r->{'files'}{$file}{'file_type'} = $4;
            $workflow_version =~ s/-/\./g;
            $r->{'files'}{$file}{'workflow_version'} = $workflow_version;
        }
    }

    return $r;
}

sub validate_submission {
    my ( $sub_path, $vcf_check ) = @_;

    my $cmd = "cgsubmit --validate-only -s $upload_url -o validation.log -u $sub_path -vv";
    say "VALIDATING: $cmd";
    unless ( $skip_validate ) {
        die "ABORT: No cgsubmit installed, aborting!" if ( system("which cgsubmit") );
        return run($cmd);
    }
    return(0);
}

# TODO: need to standardize on the return values... 1 or 0!!
sub upload_submission {
    my ($sub_path) = @_;
    my $cmd = "cgsubmit -s $upload_url -o metadata_upload.log -u $sub_path -vv -c $key";
    say "UPLOADING METADATA CMD: $cmd";
    if ( !$test && !$skip_upload ) {
        croak "ABORT: No cgsubmit installed, aborting!" if( system("which cgsubmit"));
        return 1 if ( run($cmd) );
    }

    # we need to hack the manifest.xml to drop any files that are inputs and I won't upload again
    modify_manifest_file( "$sub_path/manifest.xml", $sub_path ) unless ($test || $skip_upload);

    # Need to add code here to check for --gto-only. If it's there, call cgsubmit to generate manifest.xml,
    # then call `gtupload --gt-only...` and DO NOT call GNOS::Upload->run_upload().
    if ( $gto_only && !$test )
    {
      say "GTO Only mode is set - GTO file will be generated, but no upload will be perfomed.";
      my @now = localtime();
      my $time_stamp = sprintf("%04d-%02d-%02d-%02d-%02d-%02d",
                               $now[5]+1900, $now[4]+1, $now[3],
                               $now[2],      $now[1],   $now[0]);
      my $log_filepath = "gtupload-$time_stamp.log";
      my $gto_only_cmd = "cd $sub_path ; gtupload --gto-only -l $log_filepath -v -c $key -u ./manifest.xml";
      run($gto_only_cmd);
    }
    else
    {

      unless ( $test || $skip_upload ) {
          die "ABORT: No gtupload installed, aborting!" if ( system("which gtupload") );

      return 1 if ( GNOS::Upload->run_upload($sub_path, $key, $retries, $cooldown, $k_timeout_min) );
      }
    }
    # now make an archive tarball if requested
    if ($upload_archive ne "") {
      return 1 if (run("mkdir -p $upload_archive/$uuid && rsync -Lrauv $sub_path/* $upload_archive/$uuid/ && cd $upload_archive && tar zcf $uuid.tar.gz $uuid"));
    }

    # just touch this file to ensure monitoring tools know upload is complete
    run("date +\%s > $final_touch_file", "metadata_upload.log");

    return 0;
}

sub modify_manifest_file {
    my ( $man, $sub_path ) = @_;

    open my $out, '>', "$man.new";

    open my $in, '<', $man;
    while (<$in>) {
        chomp;
        if (/filename="([^"]+)"/) {
            if ( -e "$sub_path/$1" ) {
                say $out $_;
            }
        }
        else {
            say $out $_;
        }
    }
    close $in;
    close $out;

    system("mv $man.new $man");

    return 1;
}

sub generate_submission {

    my ( $m, $input_json_hash, $output_json_hash ) = @_;

    # const
    my $t        = gmtime;
    my $datetime = $t->datetime();

    # populate refcenter from original BAM submission
    # @RG CN:(.*)
    my $refcenter = "";

    # @CO sample_id
    my $sample_id = "";

    # capture list
    my $sample_uuids = {};

# current sample_uuid (which seems to actually be aliquot ID, this is sample ID from the BAM header)
    my $sample_uuid = "";

    # @RG SM or @CO aliquoit_id
    my $aliquot_id = "";

    # @RG LB:(.*)
    my $library = "";

    # @RG ID:(.*)
    my $read_group_id = "";

    # @RG PU:(.*)
    my $platform_unit = "";

    # @CO participant_id
    my $participant_id = "";

    # hardcoded
    my $bam_file = "";

    # hardcoded
    my $bam_file_checksum = "";

    # center name
    my $center_name = "";

    # these data are collected from all files
    # aliquot_id|library_id|platform_unit|read_group_id|input_url
    my $global_attr = {};

    # input info
    my $pi2 = {};

    # this isn't going to work if there are multiple files/readgroups!
    foreach my $file ( keys %{$m} ) {

        # populate refcenter from original BAM submission
        # @RG CN:(.*)
        $refcenter   = $m->{$file}{'target'}[0]{'refcenter'};
        $center_name = $m->{$file}{'center_name'};
        $sample_uuid = $m->{$file}{'target'}[0]{'refname'};
        $sample_uuids->{ $m->{$file}{'target'}[0]{'refname'} } = 1;

        # @CO sample_id
        my @sample_ids = keys %{ $m->{$file}{'analysis_attr'}{'sample_id'} };

        # workaround for updated XML
        if ( scalar(@sample_ids) == 0 ) {
            @sample_ids =
              keys %{ $m->{$file}{'analysis_attr'}{'submitter_specimen_id'} };
        }
        $sample_id = $sample_ids[0];

        # @RG SM or @CO aliquoit_id
        my @aliquot_ids = keys %{ $m->{$file}{'analysis_attr'}{'aliquot_id'} };

        # workaround for updated XML
        if ( scalar(@aliquot_ids) == 0 ) {
            @aliquot_ids =
              keys %{ $m->{$file}{'analysis_attr'}{'submitter_sample_id'} };
        }
        $aliquot_id = $aliquot_ids[0];

        # @RG LB:(.*)
        $library = $m->{$file}{'run'}[0]{'data_block_name'};

        # @RG ID:(.*)
        $read_group_id = $m->{$file}{'run'}[0]{'read_group_label'};

        # @RG PU:(.*)
        $platform_unit = $m->{$file}{'run'}[0]{'refname'};

        # @CO participant_id
        my @participant_ids =
          keys %{ $m->{$file}{'analysis_attr'}{'participant_id'} };
        if ( scalar(@participant_ids) == 0 ) {
            @participant_ids =
              keys %{ $m->{$file}{'analysis_attr'}{'submitter_donor_id'} };
        }
        $participant_id = $participant_ids[0];
        my $index = 0;
        foreach my $bam_info ( @{ $m->{$file}{'run'} } ) {
            if (defined($bam_info) && $bam_info->{data_block_name} ne '' ) {

                my $pi = {};
                $pi->{'input_info'}{'donor_id'}              = $participant_id;
                $pi->{'input_info'}{'specimen_id'}           = $sample_id;
                $pi->{'input_info'}{'target_sample_refname'} = $sample_uuid;
                $pi->{'input_info'}{'analyzed_sample'}       = $aliquot_id;
                $pi->{'input_info'}{'library'}               = $library;
                $pi->{'input_info'}{'platform_unit'}         = $platform_unit;
                $pi->{'read_group_id'}                       = $read_group_id;
                $pi->{'input_info'}{'analysis_id'} = $m->{$file}{'analysis_id'};
                $pi->{'input_info'}{'bam_file'} =
                  $m->{$file}{'file'}[$index]{filename};
                push @{ $pi2->{'pipeline_input_info'} }, $pi;
            }
            $index++;
        }

        # now combine the analysis attr
        foreach my $attName ( keys %{ $m->{$file}{analysis_attr} } ) {
            foreach
              my $attVal ( keys %{ $m->{$file}{analysis_attr}{$attName} } )
            {
                $global_attr->{$attName}{$attVal} = 1;
            }
        }
    }

    # override if given on the command line
    if (defined($center_override) && $center_override ne "") { $center_name = $center_override; }
    if (defined($refcenter_override) && $refcenter_override ne "") { $refcenter = $refcenter_override; }

    my $str = to_json($pi2);
    $global_attr->{"pipeline_input_info"}{$str} = 1;

    my $description =
"This is the variant calling for specimen $sample_id from donor $participant_id. The results consist of one or more VCF files plus optional tar.gz files that contain additional file types. This uses the $workflow_name workflow, version $workflow_version available at $workflow_url. This workflow can be created from source, see $workflow_src_url. For a complete change log see $changelog_url. Note the 'ANALYSIS_TYPE' is 'REFERENCE_ASSEMBLY' but a better term to describe this analysis is 'SEQUENCE_VARIATION' as defined by the EGA's SRA 1.5 schema. Please note the reference used for alignment was hs37d, see ftp://ftp.1000genomes.ebi.ac.uk/vol1/ftp/technical/reference/phase2_reference_assembly_sequence/README_human_reference_20110707 for more information. Briefly this is the integrated reference sequence from the GRCh37 primary assembly (chromosomal plus unlocalized and unplaced contigs), the rCRS mitochondrial sequence (AC:NC_012920), Human herpesvirus 4 type 1 (AC:NC_007605) and the concatenated decoy sequences (hs37d5cs.fa.gz). Variant calls may not be present for all contigs in this reference.";

    if ( $description_file ne "" && -e $description_file ) {
        local $/ = undef;
        open my $fh, '<', $description_file;
        binmode $fh;
        $description = <$fh>;
        close $fh;
    }

    my $analysis_xml = <<END;
  <ANALYSIS_SET xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://www.ncbi.nlm.nih.gov/viewvc/v1/trunk/sra/doc/SRA_1-5/SRA.analysis.xsd?view=co">
    <ANALYSIS center_name="$center_name" analysis_center="$analysis_center" analysis_date="$datetime">
      <TITLE>TCGA/ICGC PanCancer Donor-Level Variant Calling for Participant $participant_id</TITLE>
      <STUDY_REF refcenter="$refcenter" refname="$study_ref_name" />
      <DESCRIPTION>$description</DESCRIPTION>
      <ANALYSIS_TYPE>
        <REFERENCE_ALIGNMENT>
          <ASSEMBLY>
  	  <STANDARD short_name="GRCh37"/>
          </ASSEMBLY>
          <RUN_LABELS>
END
    foreach my $url ( keys %{$m} ) {
        foreach my $run ( @{ $m->{$url}{'run'} } ) {

            if ( defined( $run->{'read_group_label'} ) ) {

                my $dbn = $run->{'data_block_name'};
                my $rgl = $run->{'read_group_label'};
                my $rn  = $run->{'refname'};
                $analysis_xml .=
"              <RUN data_block_name=\"$dbn\" read_group_label=\"$rgl\" refname=\"$rn\" refcenter=\"$center_name\" />\n";
            }
        }

    }

    $analysis_xml .= <<END;
          </RUN_LABELS>
          <SEQ_LABELS>
END

    my $last_dbn = "";
    foreach my $dbn ( keys %{$sample_uuids} ) {
        $last_dbn = $dbn;
        $analysis_xml .= <<END;
            <SEQUENCE data_block_name="$dbn" accession="NC_000001.10" seq_label="1" />
            <SEQUENCE data_block_name="$dbn" accession="NC_000002.11" seq_label="2" />
            <SEQUENCE data_block_name="$dbn" accession="NC_000003.11" seq_label="3" />
            <SEQUENCE data_block_name="$dbn" accession="NC_000004.11" seq_label="4" />
            <SEQUENCE data_block_name="$dbn" accession="NC_000005.9" seq_label="5" />
            <SEQUENCE data_block_name="$dbn" accession="NC_000006.11" seq_label="6" />
            <SEQUENCE data_block_name="$dbn" accession="NC_000007.13" seq_label="7" />
            <SEQUENCE data_block_name="$dbn" accession="NC_000008.10" seq_label="8" />
            <SEQUENCE data_block_name="$dbn" accession="NC_000009.11" seq_label="9" />
            <SEQUENCE data_block_name="$dbn" accession="NC_000010.10" seq_label="10" />
            <SEQUENCE data_block_name="$dbn" accession="NC_000011.9" seq_label="11" />
            <SEQUENCE data_block_name="$dbn" accession="NC_000012.11" seq_label="12" />
            <SEQUENCE data_block_name="$dbn" accession="NC_000013.10" seq_label="13" />
            <SEQUENCE data_block_name="$dbn" accession="NC_000014.8" seq_label="14" />
            <SEQUENCE data_block_name="$dbn" accession="NC_000015.9" seq_label="15" />
            <SEQUENCE data_block_name="$dbn" accession="NC_000016.9" seq_label="16" />
            <SEQUENCE data_block_name="$dbn" accession="NC_000017.10" seq_label="17" />
            <SEQUENCE data_block_name="$dbn" accession="NC_000018.9" seq_label="18" />
            <SEQUENCE data_block_name="$dbn" accession="NC_000019.9" seq_label="19" />
            <SEQUENCE data_block_name="$dbn" accession="NC_000020.10" seq_label="20" />
            <SEQUENCE data_block_name="$dbn" accession="NC_000021.8" seq_label="21" />
            <SEQUENCE data_block_name="$dbn" accession="NC_000022.10" seq_label="22" />
            <SEQUENCE data_block_name="$dbn" accession="NC_000023.10" seq_label="X" />
            <SEQUENCE data_block_name="$dbn" accession="NC_000024.9" seq_label="Y" />
            <SEQUENCE data_block_name="$dbn" accession="NC_012920" seq_label="MT" />
            <SEQUENCE data_block_name="$dbn" accession="GL000207.1" seq_label="GL000207.1" />
            <SEQUENCE data_block_name="$dbn" accession="GL000226.1" seq_label="GL000226.1" />
            <SEQUENCE data_block_name="$dbn" accession="GL000229.1" seq_label="GL000229.1" />
            <SEQUENCE data_block_name="$dbn" accession="GL000231.1" seq_label="GL000231.1" />
            <SEQUENCE data_block_name="$dbn" accession="GL000210.1" seq_label="GL000210.1" />
            <SEQUENCE data_block_name="$dbn" accession="GL000239.1" seq_label="GL000239.1" />
            <SEQUENCE data_block_name="$dbn" accession="GL000235.1" seq_label="GL000235.1" />
            <SEQUENCE data_block_name="$dbn" accession="GL000201.1" seq_label="GL000201.1" />
            <SEQUENCE data_block_name="$dbn" accession="GL000247.1" seq_label="GL000247.1" />
            <SEQUENCE data_block_name="$dbn" accession="GL000245.1" seq_label="GL000245.1" />
            <SEQUENCE data_block_name="$dbn" accession="GL000197.1" seq_label="GL000197.1" />
            <SEQUENCE data_block_name="$dbn" accession="GL000203.1" seq_label="GL000203.1" />
            <SEQUENCE data_block_name="$dbn" accession="GL000246.1" seq_label="GL000246.1" />
            <SEQUENCE data_block_name="$dbn" accession="GL000249.1" seq_label="GL000249.1" />
            <SEQUENCE data_block_name="$dbn" accession="GL000196.1" seq_label="GL000196.1" />
            <SEQUENCE data_block_name="$dbn" accession="GL000248.1" seq_label="GL000248.1" />
            <SEQUENCE data_block_name="$dbn" accession="GL000244.1" seq_label="GL000244.1" />
            <SEQUENCE data_block_name="$dbn" accession="GL000238.1" seq_label="GL000238.1" />
            <SEQUENCE data_block_name="$dbn" accession="GL000202.1" seq_label="GL000202.1" />
            <SEQUENCE data_block_name="$dbn" accession="GL000234.1" seq_label="GL000234.1" />
            <SEQUENCE data_block_name="$dbn" accession="GL000232.1" seq_label="GL000232.1" />
            <SEQUENCE data_block_name="$dbn" accession="GL000206.1" seq_label="GL000206.1" />
            <SEQUENCE data_block_name="$dbn" accession="GL000240.1" seq_label="GL000240.1" />
            <SEQUENCE data_block_name="$dbn" accession="GL000236.1" seq_label="GL000236.1" />
            <SEQUENCE data_block_name="$dbn" accession="GL000241.1" seq_label="GL000241.1" />
            <SEQUENCE data_block_name="$dbn" accession="GL000243.1" seq_label="GL000243.1" />
            <SEQUENCE data_block_name="$dbn" accession="GL000242.1" seq_label="GL000242.1" />
            <SEQUENCE data_block_name="$dbn" accession="GL000230.1" seq_label="GL000230.1" />
            <SEQUENCE data_block_name="$dbn" accession="GL000237.1" seq_label="GL000237.1" />
            <SEQUENCE data_block_name="$dbn" accession="GL000233.1" seq_label="GL000233.1" />
            <SEQUENCE data_block_name="$dbn" accession="GL000204.1" seq_label="GL000204.1" />
            <SEQUENCE data_block_name="$dbn" accession="GL000198.1" seq_label="GL000198.1" />
            <SEQUENCE data_block_name="$dbn" accession="GL000208.1" seq_label="GL000208.1" />
            <SEQUENCE data_block_name="$dbn" accession="GL000191.1" seq_label="GL000191.1" />
            <SEQUENCE data_block_name="$dbn" accession="GL000227.1" seq_label="GL000227.1" />
            <SEQUENCE data_block_name="$dbn" accession="GL000228.1" seq_label="GL000228.1" />
            <SEQUENCE data_block_name="$dbn" accession="GL000214.1" seq_label="GL000214.1" />
            <SEQUENCE data_block_name="$dbn" accession="GL000221.1" seq_label="GL000221.1" />
            <SEQUENCE data_block_name="$dbn" accession="GL000209.1" seq_label="GL000209.1" />
            <SEQUENCE data_block_name="$dbn" accession="GL000218.1" seq_label="GL000218.1" />
            <SEQUENCE data_block_name="$dbn" accession="GL000220.1" seq_label="GL000220.1" />
            <SEQUENCE data_block_name="$dbn" accession="GL000213.1" seq_label="GL000213.1" />
            <SEQUENCE data_block_name="$dbn" accession="GL000211.1" seq_label="GL000211.1" />
            <SEQUENCE data_block_name="$dbn" accession="GL000199.1" seq_label="GL000199.1" />
            <SEQUENCE data_block_name="$dbn" accession="GL000217.1" seq_label="GL000217.1" />
            <SEQUENCE data_block_name="$dbn" accession="GL000216.1" seq_label="GL000216.1" />
            <SEQUENCE data_block_name="$dbn" accession="GL000215.1" seq_label="GL000215.1" />
            <SEQUENCE data_block_name="$dbn" accession="GL000205.1" seq_label="GL000205.1" />
            <SEQUENCE data_block_name="$dbn" accession="GL000219.1" seq_label="GL000219.1" />
            <SEQUENCE data_block_name="$dbn" accession="GL000224.1" seq_label="GL000224.1" />
            <SEQUENCE data_block_name="$dbn" accession="GL000223.1" seq_label="GL000223.1" />
            <SEQUENCE data_block_name="$dbn" accession="GL000195.1" seq_label="GL000195.1" />
            <SEQUENCE data_block_name="$dbn" accession="GL000212.1" seq_label="GL000212.1" />
            <SEQUENCE data_block_name="$dbn" accession="GL000222.1" seq_label="GL000222.1" />
            <SEQUENCE data_block_name="$dbn" accession="GL000200.1" seq_label="GL000200.1" />
            <SEQUENCE data_block_name="$dbn" accession="GL000193.1" seq_label="GL000193.1" />
            <SEQUENCE data_block_name="$dbn" accession="GL000194.1" seq_label="GL000194.1" />
            <SEQUENCE data_block_name="$dbn" accession="GL000225.1" seq_label="GL000225.1" />
            <SEQUENCE data_block_name="$dbn" accession="GL000192.1" seq_label="GL000192.1" />
            <SEQUENCE data_block_name="$dbn" accession="NC_007605" seq_label="NC_007605" />
            <SEQUENCE data_block_name="$dbn" accession="hs37d5" seq_label="hs37d5" />
END
    }

    $analysis_xml .= <<END;
          </SEQ_LABELS>
          <PROCESSING>
            <PIPELINE>
END

    if ( $pipeline_json_file ne "" && -e $pipeline_json_file ) {
        local $/ = undef;
        open my $fh, '<', $pipeline_json_file;
        binmode $fh;
        my $json = <$fh>;
        close $fh;
        my $d = decode_json($json);
        foreach my $r ( @{ $d->{'pipe'} } ) {
            my $section_name        = $r->{'section_name'};
            my $step_index          = $r->{'step_index'};
            my $previous_step_index = $r->{'previous_step_index'};
            my $program             = $r->{'program'};
            my $version             = $r->{'version'};
            my $notes               = $r->{'notes'};

            $analysis_xml .= <<END;
                    <PIPE_SECTION section_name="$section_name">
                      <STEP_INDEX>$step_index</STEP_INDEX>
                      <PREV_STEP_INDEX>$previous_step_index</PREV_STEP_INDEX>
                      <PROGRAM>$program</PROGRAM>
                      <VERSION>$version</VERSION>
                      <NOTES>$notes</NOTES>
                    </PIPE_SECTION>
END
        }

    }
    else {
        $analysis_xml .= <<END;
                  <PIPE_SECTION section_name="SeqWare_$seqware_version">
                    <STEP_INDEX>1</STEP_INDEX>
                    <PREV_STEP_INDEX>NIL</PREV_STEP_INDEX>
                    <PROGRAM>$workflow_name</PROGRAM>
                    <VERSION>$workflow_version</VERSION>
                    <NOTES></NOTES>
                  </PIPE_SECTION>
END
    }

    $analysis_xml .= <<END;
            </PIPELINE>
            <DIRECTIVES>
              <alignment_includes_unaligned_reads>true</alignment_includes_unaligned_reads>
              <alignment_marks_duplicate_reads>true</alignment_marks_duplicate_reads>
              <alignment_includes_failed_reads>false</alignment_includes_failed_reads>
            </DIRECTIVES>
          </PROCESSING>
        </REFERENCE_ALIGNMENT>
      </ANALYSIS_TYPE>
      <TARGETS>
END
    foreach my $curr_sample_uuid ( keys %{$sample_uuids} ) {
        $analysis_xml .= <<END;
        <TARGET sra_object_type="SAMPLE" refcenter="$refcenter" refname="$curr_sample_uuid" />
END
    }
    $analysis_xml .= <<END;
      </TARGETS>
      <DATA_BLOCK name=\"$last_dbn\">
        <FILES>
END

    # VCF files
    for ( my $i = 0 ; $i < scalar(@vcf_arr) ; $i++ ) {
        my $curr_vcf = $vcf_arr[$i];
        if($vcf_arr[$i] =~ /^\S*\/([^\/]+)$/) {
          $curr_vcf = $1;
        }
        my $curr_index = $vcfs_idx_arr[$i];
        if($vcfs_idx_arr[$i] =~ /^\S*\/([^\/]+)$/) {
          $curr_index = $1;
        }
        $analysis_xml .=
"          <FILE filename=\"$curr_vcf\" filetype=\"vcf\" checksum_method=\"MD5\" checksum=\"$vcf_checksums[$i]\" />\n";
        $analysis_xml .=
"          <FILE filename=\"$curr_index\" filetype=\"idx\" checksum_method=\"MD5\" checksum=\"$idx_checksums[$i]\" />\n";
    }

    # BAM files
    for ( my $i = 0 ; $i < scalar(@bam_arr) ; $i++ ) {
        my $curr_bam = $bam_arr[$i];
        if($bam_arr[$i] =~ /^\S*\/([^\/]+)$/) {
          $curr_bam = $1;
        }
        my $curr_index = $bams_bai_arr[$i];
        if($bams_bai_arr[$i] =~ /^\S*\/([^\/]+)$/) {
          $curr_index = $1;
        }
        $analysis_xml .=
    "          <FILE filename=\"$curr_bam\" filetype=\"bam\" checksum_method=\"MD5\" checksum=\"$bam_checksums[$i]\" />\n";
        $analysis_xml .=
    "          <FILE filename=\"$curr_index\" filetype=\"bai\" checksum_method=\"MD5\" checksum=\"$bai_checksums[$i]\" />\n";
    }

    # Tarball files
    for ( my $i = 0 ; $i < scalar(@tarball_arr) ; $i++ ) {
        my $curr_tar = $tarball_arr[$i];
        if ($tarball_arr[$i] =~ /^\S*\/([^\/]+)$/) {
          $curr_tar = $1;
        }
        $analysis_xml .=
"          <FILE filename=\"$curr_tar\" filetype=\"tar\" checksum_method=\"MD5\" checksum=\"$tarball_checksums[$i]\" />\n";
    }

    $analysis_xml .= <<END;
        </FILES>
      </DATA_BLOCK>
      <ANALYSIS_ATTRIBUTES>
END

# this is a merge of the key-values from input XML
# changing some key names to prevent conflicts
# I'm actually now skipping a lot more than before since 1) combining multiple inputs makes this more complex, 2) I have a nice JSON that describes inputs/outputs and 3) folks can look back at the original BAM analysis.xml for more details if they need it, no need to duplicate here.
    foreach my $key ( keys %{$global_attr} ) {
        foreach my $val ( keys %{ $global_attr->{$key} } ) {
            if ( $key eq "pipeline_input_info" ) {

                #$key = "alignment_pipeline_input_info";
                next;
            }
            elsif ( $key eq "workflow_name" ) {
                $key = "alignment_workflow_name";
            }
            elsif ( $key eq "workflow_version" ) {
                $key = "alignment_workflow_version";
            }
            elsif ( $key eq "workflow_source_url" ) {
                $key = "alignment_workflow_source_url";
            }
            elsif ( $key eq "workflow_bundle_url" ) {
                $key = "alignment_workflow_bundle_url";
            }
            elsif ( $key eq "workflow_output_bam_contents" ) {

                #$key = "alignment_workflow_output_bam_contents";
                next;
            }
            elsif ( $key eq "qc_metrics" ) {

                #$key = "alignment_qc_metrics";
                next;
            }
            elsif ( $key eq "timing_metrics" ) {

                #$key = "alignment_timing_metrics";
                next;
            }
            elsif ( $key eq "markduplicates_metrics" ) {

                #$key = "alignment_markduplicates_metrics";
                next;
            }
            elsif ( $key eq "bwa_version" ) {

                #$key = "alignment_bwa_version";
                next;
            }
            elsif ( $key eq "biobambam_version" ) {

                #$key = "alignment_biobambam_version";
                next;
            }
            elsif ( $key eq "PCAP-core_version" ) {

                #$key = "alignment_PCAP-core_version";
                next;
            }
            elsif ($key eq "total_lanes"
                || $key eq "dcc_specimen_type"
                || $key eq "use_cntl"
                || $key eq "submitter_specimen_id"
                || $key eq "submitter_sample_id" )
            {
                #$key = "alignment_PCAP-core_version";
                next;
            }

            $analysis_xml .= "        <ANALYSIS_ATTRIBUTE>
          <TAG>$key</TAG>
          <VALUE>$val</VALUE>
        </ANALYSIS_ATTRIBUTE>
";
        }
    }

    # TODO
    # variant_pipeline_input_info
    $analysis_xml .= "        <ANALYSIS_ATTRIBUTE>
          <TAG>variant_pipeline_input_info</TAG>
          <VALUE>" . &to_json($input_json_hash) . "</VALUE>
        </ANALYSIS_ATTRIBUTE>
";

    # TODO
    # variant_pipeline_output_info
    $analysis_xml .= "        <ANALYSIS_ATTRIBUTE>
          <TAG>variant_pipeline_output_info</TAG>
          <VALUE>" . &to_json($output_json_hash) . "</VALUE>
        </ANALYSIS_ATTRIBUTE>
";

    # some metadata about this workflow
    $analysis_xml .= "        <ANALYSIS_ATTRIBUTE>
          <TAG>variant_workflow_name</TAG>
          <VALUE>$workflow_name</VALUE>
        </ANALYSIS_ATTRIBUTE>
        <ANALYSIS_ATTRIBUTE>
          <TAG>variant_workflow_version</TAG>
          <VALUE>$workflow_version</VALUE>
        </ANALYSIS_ATTRIBUTE>
        <ANALYSIS_ATTRIBUTE>
          <TAG>variant_workflow_source_url</TAG>
          <VALUE>$workflow_src_url</VALUE>
        </ANALYSIS_ATTRIBUTE>
        <ANALYSIS_ATTRIBUTE>
          <TAG>variant_workflow_bundle_url</TAG>
          <VALUE>$workflow_url</VALUE>
        </ANALYSIS_ATTRIBUTE>
";

    # attributes linking multiple uploads for a single workflow together
    if ($workflow_file_subset ne "") {
      $analysis_xml .= "        <ANALYSIS_ATTRIBUTE>
            <TAG>workflow_file_subset</TAG>
            <VALUE>$workflow_file_subset</VALUE>
          </ANALYSIS_ATTRIBUTE>
          ";
    }
    if ($related_file_subset_uuids ne "") {
      $analysis_xml .= "        <ANALYSIS_ATTRIBUTE>
            <TAG>related_file_subset_uuids</TAG>
            <VALUE>$related_file_subset_uuids</VALUE>
          </ANALYSIS_ATTRIBUTE>
          ";
    }

    # some metadata about this vm
    $analysis_xml .= "        <ANALYSIS_ATTRIBUTE>
          <TAG>vm_instance_type</TAG>
          <VALUE>$vm_instance_type</VALUE>
        </ANALYSIS_ATTRIBUTE>
        <ANALYSIS_ATTRIBUTE>
          <TAG>vm_instance_cores</TAG>
          <VALUE>$vm_instance_cores</VALUE>
        </ANALYSIS_ATTRIBUTE>
        <ANALYSIS_ATTRIBUTE>
          <TAG>vm_instance_mem_gb</TAG>
          <VALUE>$vm_instance_mem_gb</VALUE>
        </ANALYSIS_ATTRIBUTE>
        <ANALYSIS_ATTRIBUTE>
          <TAG>vm_location_code</TAG>
          <VALUE>$vm_location_code</VALUE>
        </ANALYSIS_ATTRIBUTE>
";

    # TODO QC
    $analysis_xml .= "        <ANALYSIS_ATTRIBUTE>
          <TAG>variant_qc_metrics</TAG>
          <VALUE>" . &getQcResult() . "</VALUE>
        </ANALYSIS_ATTRIBUTE>
";

    # TODO Runtime
    $analysis_xml .= "        <ANALYSIS_ATTRIBUTE>
          <TAG>variant_timing_metrics</TAG>
          <VALUE>" . &getRuntimeInfo() . "</VALUE>
        </ANALYSIS_ATTRIBUTE>
";

    $analysis_xml .= <<END;
      </ANALYSIS_ATTRIBUTES>
    </ANALYSIS>
  </ANALYSIS_SET>
END

    open my $out, '>', "$output_dir/analysis.xml";
    print $out $analysis_xml;
    close $out;

    # make a uniq list of blocks
    my $uniq_exp_xml = {};
    foreach my $url ( keys %{$m} ) {
        $uniq_exp_xml->{ $m->{$url}{'experiment'} } = 1;
    }

    my $exp_xml = <<END;
  <EXPERIMENT_SET xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://www.ncbi.nlm.nih.gov/viewvc/v1/trunk/sra/doc/SRA_1-5/SRA.experiment.xsd?view=co">
END

    foreach my $curr_xml_block ( keys %{$uniq_exp_xml} ) {
        $exp_xml .= $curr_xml_block;
    }

    $exp_xml .= <<END;
  </EXPERIMENT_SET>
END

    if ($make_expxml) {
        open my $out, '>', "$output_dir/experiment.xml";
        say $out $exp_xml;
        close $out;
    }

    # make a uniq list of blocks
    my $uniq_run_xml = {};
    foreach my $url ( keys %{$m} ) {
        my $run_block = $m->{$url}{'run_block'};

# no longer modifying the run block, this is the original input reads *not* the aligned BAM result!
#$run_block =~ s/filename="\S+"/filename="$bam_check.bam"/g;
#$run_block =~ s/checksum="\S+"/checksum="$bam_check"/g;
#$run_block =~ s/center_name="[^"]+"/center_name="$refcenter"/g;
        $uniq_run_xml->{$run_block} = 1;
    }

    my $run_xml = <<END;
  <RUN_SET xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://www.ncbi.nlm.nih.gov/viewvc/v1/trunk/sra/doc/SRA_1-5/SRA.run.xsd?view=co">
END

    foreach my $run_block ( keys %{$uniq_run_xml} ) {
        $run_xml .= $run_block;
    }

    $run_xml .= <<END;
  </RUN_SET>
END

    if ($make_runxml) {
        open my $out, '>', "$output_dir/run.xml";
        print $out $run_xml;
        close $out;
    }

    return ($output_dir);

}

sub read_header {
    my ($header) = @_;

    my $hd = {};
    open my $header_fh, '<', $header;
    while (<$header_fh>) {
        chomp;
        my @a    = split /\t+/;
        my $type = $a[0];
        if ( $type =~ /^@/ ) {
            $type =~ s/@//;
            for ( my $i = 1 ; $i < scalar(@a) ; $i++ ) {
                $a[$i] =~ /^([^:]+):(.+)$/;
                $hd->{$type}{$1} = $2;
            }
        }
    }
    close $header_fh;

    return $hd;
}

sub download_metadata {
    my ($urls_str, $paths_str) = @_;
    my $metad = {};
    run("mkdir -p xml2");
    my @urls = split /,/, $urls_str;
    my @paths;
    if ($paths_str ne "" && length($paths_str) > 0) {
      @paths = split /,/, $paths_str;
    }
    my $i = 0;
    foreach my $url (@urls) {
        my $file_path = $paths[$i];
        $i++;
        my $xml_path = download_url( $url,  "xml2/data_$i.xml", $file_path );
        $metad->{$url} = parse_metadata($xml_path);
    }
    #TODO: Error handline: This should thrown an error if there's no metadata at the metadata URL!!
    return ($metad);
}

sub parse_metadata {
    my ($xml_path) = @_;
    my $doc        = $parser->parsefile($xml_path);
    my $m          = {};
    $m->{'analysis_id'} = getVal( $doc, 'analysis_id' );
    $m->{'center_name'} = getVal( $doc, 'center_name' );
    push @{ $m->{'study_ref'} },
      getValsMulti( $doc, 'STUDY_REF', "refcenter,refname" );
    push @{ $m->{'run'} },
      getValsMulti( $doc, 'RUN', "data_block_name,read_group_label,refname" );
    push @{ $m->{'target'} },
      getValsMulti( $doc, 'TARGET', "refcenter,refname" );
    push @{ $m->{'file'} },
      getValsMulti( $doc, 'FILE', "checksum,filename,filetype" );
    $m->{'analysis_attr'} = getAttrs($doc);
    $m->{'experiment'}    = getBlock( $xml_path,
        "/ResultSet/Result/experiment_xml/EXPERIMENT_SET/EXPERIMENT" );
    $m->{'run_block'} =
      getBlock( $xml_path, "/ResultSet/Result/run_xml/RUN_SET/RUN" );
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
    my ( $url, $path, $alt_path ) = @_;

    if (-e $alt_path) {
      my $response = run("cp $alt_path $path");
      die "PROBLEMS COPYING FILE: 'cp $alt_path $path'" if ($response);
    }
    elsif ($url =~ /^https:\/\// || $url =~ /^http:\/\//) {
      my $response = run("wget -q -O $path $url");
      if ($response) {
        $ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 0;
        $response = run("lwp-download $url $path");
        if ($response) {
          say "ERROR DOWNLOADING: $url";
          exit 1;
        }
      }
    }
    return $path;
}

sub getVal {
    my ( $node, $key ) = @_;

    if (!defined($node)) { return undef; }

    if ( defined($node) && $node != undef ) {
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

# doesn't work
sub getVals {
    my ( $node, $key, $tag ) = @_;

    my @r;
    if ( $node != undef ) {
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
#return($node->getElementsByTagName($key)->item(0)->getFirstChild->getNodeValue);
                        foreach my $aNode ( $node->getElementsByTagName($key) )
                        {
                            # left off here
                            if ( defined($tag) ) { }
                            else {
                                push @r, $aNode->getFirstChild->getNodeValue;
                            }
                        }
                    }
                }
            }
        }
    }
    return (@r);
}

# Sheldon TODO: will need to be updated to support a more generic format
sub getRuntimeInfo {
    my $ret;
    if ( defined $timing_json_file && -e $timing_json_file ) {
        open my $qc_fh, '<', $timing_json_file or die $!;
        my $json = <$qc_fh>;
        chomp $json;
        $ret = qq{{"timing_metrics":$json}};
    }
    else {
        my $object = { "timing_metrics" => {} };
        $ret = to_json $object;
    }
    return $ret;

}

sub read_timing {
    my ($file) = @_;
    open my $in, '<', $file
      or return
      "not_collected"
      ; # very quick workaround to deal with no download_timing file generated due to skip gtdownload option. Brian, please handle it as you see it appropriate
    my $start = <IN>;
    my $stop  = <IN>;
    chomp $start;
    chomp $stop;
    my $delta = $stop - $start;
    close IN;
    return ($delta);
}

# TODO
sub getQcResult {
    my $ret;

    if ( defined $qc_json_file && -e $qc_json_file ) {
        open my $qc_fh, '<', $qc_json_file;
        my $json = <$qc_fh>;
        chomp $json;
        $ret = qq{{"qc_metrics":$json}};
    }
    else {
        my $object = { "qc_metrics" => {} };
        $ret = to_json $object;
    }

    return $ret;
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
