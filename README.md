# Overview

This repository contains several GNOS tool wrappers that attempt to make it more
robust to download and upload data for the PCAWG project.

The download wrapper monitors download progress and automatically kills and resumes
if the download is stuck.

The upload tools are designed to upload one or more VCF/tar.gz/index files produced during variant calling.  They are designed to be called as a step in a workflow or manually if needed.  gnos_upload_vcf.pl uploads files to a gnos repository and synapse_upload_vcf uploads files to the NCI Jamboree site and adds metadata and provenance to Synapse.

These tool needs to produce VCF uploads that conform to the PanCancer VCF upload spec, see https://wiki.oicr.on.ca/display/PANCANCER/PCAWG+VCF+Submission+SOP+-+v1.0

  * [GNOS upload](#gnos-upload)
  * [Synapse upload](#synapse-upload)

## Availability

You can find these tools pre-installed in a docker container, see [pancancer_upload_download](https://github.com/ICGC-TCGA-PanCancer/pancancer_upload_download).

# GNOS Download

This is a simple wrapper around gtdownload that attempts to restart the process if download
progress is not made in the timeout specified.  This is in addition to the `-k` GNOS parameter
that will cause gtdownload to exist if inactive for a certain period of time.

    USAGE: gnos_download_file.pl --pem <pem_path> --url <download_gnos_url> --file <output_file_to_check> [--retries 30] [--timeout-min 60] [--max-children <gtdownload_default>] [--rate-limit-mbytes <gtdownload_default>] [--k-timeout <minutes_of_inactivity_to_abort_recommend_less_than_timeout_if_you_want_this_to_be_used>]

# GNOS upload

## Dependencies for gnos_upload_vcf.pl

If you are using the Docker version everything will be setup for you.  If not, you
 can use PerlBrew (or your native package manager) to install dependencies.  For example:

    cpanm XML::DOM XML::XPath XML::XPath::XMLParser JSON Data::UUID XML::LibXML Time::Piece

Or on an Ubuntu 12.04 host you would install via:

    sudo apt-get install libxml-dom-perl libxml-xpath-perl libjson-perl libxml-libxml-perl time libdata-uuid-libuuid-perl libcarp-always-perl libipc-system-simple-perl

Once these are installed you can execute the script with the command below. For workflows and VMs used in the project, these dependencies will be pre-installed on the VM running the variant calling workflows.

You also need the gtdownload/gtuplod/cgsubmit tools installed.  These are available on the CGHub site and are only available for Linux (for the submission tools).

Finally, this tool uses the [GNOS upload/download wrapper library](https://github.com/ICGC-TCGA-PanCancer/gt-download-upload-wrapper) written by Adam Wright.

## Inputs

The variant calling working group has established naming conventions for the files submitted from variant calling workflows.  See https://wiki.oicr.on.ca/display/PANCANCER/PCAWG+VCF+Submission+SOP+-+v1.0.

This tool is designed to work with the following file types:

* vcf.gz: VCF file http://samtools.github.io/hts-specs/VCFv4.2.pdf compressed with 'bgzip <filename.vcf>', see http://vcftools.sourceforge.net/perl_module.html
* vcf.gz.idx: tabix index generated with 'tabix -p vcf foo.vcf.gz; mv foo.vcf.gz.tbi foo.vcf.gz.idx'
* vcf.gz.md5: md5sum file made with 'md5sum foo.vcf.gz | awk '{print$1}' > foo.vcf.gz.md5'
* vcf.gz.idx.md5: md5sum file make with 'md5sum foo.vcf.gz.idx | awk '{print$1}' > foo.vcf.gz.idx.md5'

And we also have a generic container format for files other than VCF/IDX file types:

* tar.gz: a standard tar/gz file format made with something similar to 'tar zcf bar.tar.gz <files>'. The tar.gz file must contain a README file that describes its contents
* tar.gz.md5: md5sum file made with something like 'md5sum bar.tar.gz | awk '{print$1}' > bar.tar.gz.md5'.

The files should be named using the following conventions (again, see https://wiki.oicr.on.ca/display/PANCANCER/PCAWG+VCF+Submission+SOP+-+v1.0):

| Datatype              | Required Files                                | Optional Files       |
|-----------------------|-----------------------------------------------|----------------------|
| SNV, MNV              | $META.snv_mnv.vcf.gz $META.snv_mnv.vcf.gz.tbi | $META.snv_mnv.tar.gz |
| Indel                 | $META.indel.vcf.gz $META.indel.vcf.gz.tbi     | $META.indel.tar.gz   |
| Structural Variation  | $META.sv.vcf.gz $META.sv.vcf.gz.tbi           | $META.sv.tar.gz      |
| Copy Number Variation | $META.cnv.vcf.gz $META.cnv.vcf.gz.tbi         | $META.cnv.vcf.gz     |

The $META data string must be made up of the following fields (with "." as a field separator):

| Field            | Description                                   | Example                              |
|------------------|-----------------------------------------------|--------------------------------------|
| Sample ID        | SM field from BAM, aka ICGC Specimen UUID     | 7d7205e8-d864-11e3-be46-bd5eb93a18bb |
| Pipeline-Version | Pipeline name plus the version, "_" seperated with "-" for the version string | BroadCancerAnalysis_1-0-0            |
| Date             | Date of creation                              | yyyymmdd                             |
| Type             | "somatic" or "germline"                       | "somatic" or "germline"              |

There may be multiple somatic call file sets each with different samples IDs if, for example, there is a cell-line, metastasis, second tumor sample, etc.  There should be one set of germline files.

Note: the variant calling working group has specified ".tbi" rather than ".idx" as the tabix index extension. I have asked Annai to add support for ".tbi" and will update the code to standardize on this once the GNOS changes have been made.  Also, a README needs to be included in each tar.gz file to document the contents. In the pilot this was a separate README file but GNOS does not support uploading this directly and, therefore, it needs to included in the tar.gz file.

## Running gnos_upload_vcf

The parameters:

    USAGE: 'perl gnos_upload_vcf.pl
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
     [--k-timeout-min <60>]
     [--retries <3>]
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

An example for the files that have been checked in along with this code:

    cd sample_files
    perl -I ../../gt-download-upload-wrapper/lib ../gnos_upload_vcf.pl \
    --metadata-urls https://gtrepo-osdc-icgc.annailabs.com/cghub/metadata/analysisFull/d1747d83-f0be-4eb1-859b-80985421a38e,https://gtrepo-osdc-icgc.annailabs.com/cghub/metadata/analysisFull/97146325-910b-48ae-8f4d-c2ae976b3087 \
    --vcfs 914ee592-e855-43d3-8767-a96eb6d1f067.TestWorkflow_1-0-0.20141009.germline.snv_mnv.vcf.gz,914ee592-e855-43d3-8767-a96eb6d1f067.TestWorkflow_1-0-0.20141009.germline.indel.vcf.gz,a4beedc3-0e96-4e1c-90b4-3674dfc01786.TestWorkflow_1-0-0.20141009.somatic.indel.vcf.gz,a4beedc3-0e96-4e1c-90b4-3674dfc01786.TestWorkflow_1-0-0.20141009.somatic.snv_mnv.vcf.gz \
    --vcf-md5sum-files 914ee592-e855-43d3-8767-a96eb6d1f067.TestWorkflow_1-0-0.20141009.germline.snv_mnv.vcf.gz.md5,914ee592-e855-43d3-8767-a96eb6d1f067.TestWorkflow_1-0-0.20141009.germline.indel.vcf.gz.md5,a4beedc3-0e96-4e1c-90b4-3674dfc01786.TestWorkflow_1-0-0.20141009.somatic.indel.vcf.gz.md5,a4beedc3-0e96-4e1c-90b4-3674dfc01786.TestWorkflow_1-0-0.20141009.somatic.snv_mnv.vcf.gz.md5 \
    --vcf-idxs 914ee592-e855-43d3-8767-a96eb6d1f067.TestWorkflow_1-0-0.20141009.germline.snv_mnv.vcf.gz.idx,914ee592-e855-43d3-8767-a96eb6d1f067.TestWorkflow_1-0-0.20141009.germline.indel.vcf.gz.idx,a4beedc3-0e96-4e1c-90b4-3674dfc01786.TestWorkflow_1-0-0.20141009.somatic.indel.vcf.gz.idx,a4beedc3-0e96-4e1c-90b4-3674dfc01786.TestWorkflow_1-0-0.20141009.somatic.snv_mnv.vcf.gz.idx \
    --vcf-idx-md5sum-files 914ee592-e855-43d3-8767-a96eb6d1f067.TestWorkflow_1-0-0.20141009.germline.snv_mnv.vcf.gz.idx.md5,914ee592-e855-43d3-8767-a96eb6d1f067.TestWorkflow_1-0-0.20141009.germline.indel.vcf.gz.idx.md5,a4beedc3-0e96-4e1c-90b4-3674dfc01786.TestWorkflow_1-0-0.20141009.somatic.indel.vcf.gz.idx.md5,a4beedc3-0e96-4e1c-90b4-3674dfc01786.TestWorkflow_1-0-0.20141009.somatic.snv_mnv.vcf.gz.idx.md5 \
    --tarballs 914ee592-e855-43d3-8767-a96eb6d1f067.TestWorkflow_1-0-0.20141009.germline.snv_mnv.tar.gz,914ee592-e855-43d3-8767-a96eb6d1f067.TestWorkflow_1-0-0.20141009.germline.indel.tar.gz,a4beedc3-0e96-4e1c-90b4-3674dfc01786.TestWorkflow_1-0-0.20141009.somatic.snv_mnv.tar.gz \
    --tarball-md5sum-files 914ee592-e855-43d3-8767-a96eb6d1f067.TestWorkflow_1-0-0.20141009.germline.snv_mnv.tar.gz.md5,914ee592-e855-43d3-8767-a96eb6d1f067.TestWorkflow_1-0-0.20141009.germline.indel.tar.gz.md5,a4beedc3-0e96-4e1c-90b4-3674dfc01786.TestWorkflow_1-0-0.20141009.somatic.snv_mnv.tar.gz.md5 \
    --outdir test --key test.pem \
    --upload-url https://gtrepo-ebi.annailabs.com \
    --study-refname-override icgc_pancancer_vcf_test --test

Something to note from the above, you cloud run the uploader multiple times with different sets of files (germline, somatic, etc). We want to avoid that for variant calling workflows for the simple reason that a single record in GNOS is much easier to understand than multiple analysis records for each individual set of files.

## Test Data

The sample command above is using the Donor ICGC_0437 as an example:

    # the tumor
    SPECIMEN/SAMPLE: 8051719
        ANALYZED SAMPLE/ALIQUOT: 8051719
            LIBRARY: WGS:QCMG:Library_20121203_T
                TUMOR: https://gtrepo-osdc-icgc.annailabs.com/cghub/metadata/analysisFull/97146325-910b-48ae-8f4d-c2ae976b3087
                SAMPLE UUID: a4beedc3-0e96-4e1c-90b4-3674dfc01786

    SPECIMEN/SAMPLE: 8051442
        ANALYZED SAMPLE/ALIQUOT: 8051442
            LIBRARY: WGS:QCMG:Library_20121203_U
                NORMAL: https://gtrepo-osdc-icgc.annailabs.com/cghub/metadata/analysisFull/d1747d83-f0be-4eb1-859b-80985421a38e
                SAMPLE UUID: 914ee592-e855-43d3-8767-a96eb6d1f067

You can find fake examples of VCF, tarball, and associated files in the "sample_files" directory.

## Timing JSON Format

This JSON format lets you specify runtime information for recording in the analysis.xml metadata submission file.

TODO: Sheldon, you'll want to define a JSON format for this

## QC JSON Format

This JSON format lets you specify QC statistics for recording in the analysis.xml metadata submission file.

TODO: Sheldon, you'll want to define a JSON format for this

## Pipe JSON Format

This JSON format lets you specify details about the individual steps of the workflow.  If this is not specified than a single step will be recorded in the analysis.xml metadata file that reflects the name and version of the workflow.

The format of the Pipe JSON for that section of the XML:

    {
      "pipe": [
        ...,
        {
          "section_name": "name",
          "step_index": "2",
          "previous_step_index": "1",  
          "program": "tool name",
          "version": "1.2.1",
          "notes": "typically params used as a string"
        },
        ...
      ]
    }

## Notes About GNOS Analysis XML

The tool encodes various metadata in an analysis.xml for uploading to GNOS.  Here's some additional information about what is populated in some key fields that folks on the project have asked about.

    <ANALYSIS center_name="UCSC" analysis_center="OICR" analysis_date="2014-12-04T20:11:46”>

In this element, center_name is carried over from the input XML (no mechanism to override in workflow/VCF uploader).

analysis_center defaults to OICR but can be overridden by a parameter to the workflow/VCF uploader.

    <STUDY_REF refcenter="TCGA" refname="tcga_pancancer_vcf_test”/>

refcenter is carried over from the input XML (no mechanism to override in workflow/VCF uploader).

refname defaults to “icgc_pancancer_vcf” but can be overridden by a parameter to the workflow/VCF uploader.

### Values for the Core 60 Donors

For the TCGA samples (which are most of the 60) this should be “tcga\_pancancer\_vcf\_test”.  For the ICGC samples its “icgc\_pancancer\_vcf\_test”.  Given the churn that happened last time with the alignment workflow I think it makes sense to keep the 60 in the “test” studies and switch over to the real one once the full set of donors are running.

# Troubleshooting

## Stuck Uploads

On occasional (the specific circumstances are unclear as to whether this is a client or server issue), uploads will stall. To diagnose this, you can find the log that is generated for a specific run.  

    [WORKER] ubuntu@i-3108bb9c:/datastore/oozie-68bd43b3-278d-4f9c-a405-190d3819656f/data/632fef40-ef8d-4c0a-8d32-a6b7f03546ab$ tail -n 100 gtupload-2015-08-05-01-20-41.log
    08/05 13:55:39.033 Normal:  632fef40-ef8d-4c0a-8d32-a6b7f03546ab (https://gttracker-ebi.annailabs.com:21111/tracker.php/announce) sending announce (none), infohash:  75ad485d3bf72fa7aed0c8155ff4a0a717f3355e
    08/05 13:55:39.083 Normal:  632fef40-ef8d-4c0a-8d32-a6b7f03546ab (https://gttracker-ebi.annailabs.com:21111/tracker.php/announce) received peers: 0, infohash:  75ad485d3bf72fa7aed0c8155ff4a0a717f3355e
    08/05 13:55:43.389 Normal:  Status: 0 bytes uploaded (0.000% complete) current rate:
    08/05 13:55:48.396 Normal:  Status: 0 bytes uploaded (0.000% complete) current rate:
    08/05 13:55:53.403 Normal:  Status: 0 bytes uploaded (0.000% complete) current rate:
    08/05 13:55:58.410 Normal:  Status: 0 bytes uploaded (0.000% complete) current rate:

If it looks stuck like this, you can use top to identify the perl wrapper script and gtupload process. *Make sure that you kill the perl script first*. If you kill the actual gtupload process, it will report an exit code of zero as if there were no problems and the workflow will immediately proceed onwards. 

    [WORKER] ubuntu@i-3108bb9c:/datastore/oozie-68bd43b3-278d-4f9c-a405-190d3819656f/data/632fef40-ef8d-4c0a-8d32-a6b7f03546ab$ top -c
    ...                                                   
     6236 ubuntu    20   0 19.830g 210928   2444 S   0.0  0.3  17:11.87 java -cp pancancer-arch-3-1.1-beta.3.jar info.pancancer.arch3.worker.Worker --uuid i-3108bb9c --config workerConfig.ini --pidFile /var/run/arch+
     6352 ubuntu    20   0 19.179g 134300   2600 S   0.0  0.2   6:26.44 java io.seqware.cli.Main bundle launch --dir /workflow --ini /ini --no-metadata --engine whitestar
    13910 ubuntu    20   0 2133716  29120   8488 S   0.0  0.0   0:16.64 /workflow/Workflow_Bundle_BWA/2.6.5/bin/jre1.7.0_51/bin/java -Xmx500M -classpath /workflow/Workflow_Bundle_BWA/2.6.5/lib/seqware-distribution-1+
     1128 syslog    20   0  260460  27216    860 S   0.0  0.0   0:14.62 rsyslogd
    13932 ubuntu    20   0   75980  22404   2984 S   0.0  0.0   0:59.87 perl -I/workflow/Workflow_Bundle_BWA/2.6.5/bin/gt-download-upload-wrapper-2.0.10/lib /workflow/Workflow_Bundle_BWA/2.6.5/scripts/gnos_upload_da+
     6047 sensu     20   0 1435896  20320   2868 S   0.0  0.0  16:15.51 /opt/sensu/embedded/bin/ruby /opt/sensu/bin/sensu-client -b -c /etc/sensu/config.json -d /etc/sensu/conf.d -e /etc/sensu/extensions -p /var/run+
    13965 ubuntu    20   0  382828  15952  12600 S   0.0  0.0  35:20.50 gtupload -l gtupload-2015-08-05-01-20-41.log -v -c /home/ubuntu/.gnos/gnos.pem -u ./manifest.xml
    ....
    [WORKER] ubuntu@i-3108bb9c:/datastore/oozie-68bd43b3-278d-4f9c-a405-190d3819656f/data/632fef40-ef8d-4c0a-8d32-a6b7f03546ab$ kill -9 13932
    [WORKER] ubuntu@i-3108bb9c:/datastore/oozie-68bd43b3-278d-4f9c-a405-190d3819656f/data/632fef40-ef8d-4c0a-8d32-a6b7f03546ab$ kill -9 13965

If executed through SeqWare, the workflow will then receive a correct non-zero exit code and retry the upload. The number of times SeqWare will retry is based on the ~/.seqware/settings file (normally 5 by default if not specified in that file). 

You can verify by looking in top again and you should see a new gtupload process with a different PID. 



## To Do

* removed hard coded XML files and replace with Template Toolkit templates (or something similar)
* validation needs to be implemented:
    * need to make sure each file conforms to the naming convention
    * need to ensure the headers (and contents) of VCF conform to the upload SOP, see https://wiki.oicr.on.ca/display/PANCANCER/PCAWG+VCF+Submission+SOP+-+v1.0
    * need to run the VCF files through VCFTools validation
* if not provided as files/params, compute the md5sums for the submitted files

# Synapse upload

## Dependencies for synapse_upload_vcf

You will need to have the Python synapseclient installed.  Details for installing and setting up credentials is described in the research guide (under "How to Get Access to Synapse") see: https://wiki.oicr.on.ca/display/PANCANCER/PCAWG+Researcher%27s+Guide


Make sure python dev is installed

    sudo apt-get install python-dev python-pip

In short use the pip command to install the python packages (use the --upgrade flag if older versions are already installed)

    sudo pip install synapseclient
    sudo pip install python-dateutil
    sudo pip install elasticsearch
    sudo pip install xmltodict
    sudo pip install pysftp
    sudo pip install paramiko

In addition it helps to add your credentials so that you don't have to rewrite your username/password.  This can be done (only needs to be done once) by typing

    synapse login -u <synapse username> -p <synapse password>  --rememberMe

In additon you can cache your jamboree credentials by adding them to a config file (see above research guide)

    ~/.synapseConfig
    [sftp://tcgaftps.nci.nih.gov]
    username = Username
    password = password


## Running synapse_upload_vcf

The synapse upload script uses a json file with paremeters (see [example_input.json](https://github.com/ICGC-TCGA-PanCancer/vcf-uploader/blob/develop/sample_files/example_input.json) and a parentId which reprsents the folder in Synapse to upload the files to.  For example to upload the example files to DKFZ output folder:

     synapse_upload_vcf --parentId syn2898426 sample_files/example_input.json

to upload Sanger files but store them at a specific spot in the sftp site:

     synapse_upload_vcf --parentId syn3155834 --url sftp://tcgaftps.nci.nih.gov/tcgapancan/pancan/Sanger_workflow_variants sample_files/example_input.json

## Wrapper script for synapse_upload_vcf

The use case for bulk uploading to synapse is that the files and metadata are in GNOS and not locally stored.  The perl script synapse_upload_vcf.pl will use elastic search to get the metadata URLs, inititally for the pilot set, grab the metadata from GNOS, download all of the analysis files, then stage the upload to synapse.  The JSON files are stored locally. Running synapse_upload_vcf (as above) is handled by synapse_upload_vcf.pl.  One oustanding issue is that it is not clear where the parentID should be coming from.  synapse_upload_vcf.pl can also be run with a single metadata URL.

    Usage: synapse_upload_vcf.pl[--metadata-url url]
                                [--use-cached_xml]
                                [--local-xml /path/to/local/metadata.xml -- Note: still downloads BWA metadata from GNOS]
                                [--metadata-url-file /path/to/metadata_url_file -- a list of metadata urls]
                                [--output-dir dir]
                                [--xml-dir]
                                [--pem-file file.pem]
                                [--parent-id syn2897245]
                                [--pem-conf conf/pem.conf]
                                [--local-path /path/to/local/files]
                                [--jamboree-sftp-url url of files that are ALREADY UPLOADED on the jamboree sftp server]
      			        [--synapse-sftp-url url to which files WILL BE UPLOADED via synapse]
                                [--download optional flag to Download files from GNOS]
                                [--help]

<b>NOTE:</b> If you are using different pem files on different servers, use either the --pem-file or --pem-conf arguments below]

<b>Example: use a batch of GNOS metadata URLs, download VCF files from GNOS (batch mode)</b>

    ./synapse_upload_vcf.pl --metadata-url-file sample_files/metadata_urls.txt --download

<b>Example: use a single metadata URL, download VCF files from GNOS</b>

    ./synapse_upload_vcf.pl --metadata-url https://gtrepo-osdc-tcga.annailabs.com/cghub/metadata/analysisFull/ee33425e-4384-4245-9d59-ea96d899e790 --download

<b>Example: use a local metadata xml file</b>

    ./synapse_upload_vcf.pl --local-xml xml/data_ee33425e-4384-4245-9d59-ea96d899e790.xml

<b>Example: use elastic search to get metadata URLs (default); provide the jamboree sftp URL for the files (no local files)

    ./synapse_upload_vcf.pl --jamboree-sftp-url sftp://tcgaftps.nci.nih.gov/tcgapancan/pancan/Sanger_workflow_variants/batch01

<b>Example: use a local metadata xml file; upload vcf files to synapse using a local file path</b>

    ./synapse_upload_vcf.pl --local-xml xml/data_ee33425e-4384-4245-9d59-ea96d899e790.xml --local-path vcf/test_output_dir

<b>Example: use local metadata xml and local files, specify the sftp URL for synapse to use</b>

    ./synapse_upload_vcf.pl --local-xml xml/data_ee33425e-4384-4245-9d59-ea96d899e790.xml \
    --local-path vcf/test_output_dir \
    --synapse_sftp_url sftp://tcgaftps.nci.nih.gov/tcgapancan/pancan/Sanger_workflow_variants/batch01
