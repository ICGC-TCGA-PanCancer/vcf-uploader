# README

## Overview

This tool is designed to upload one or more VCF/tar.gz/index files produced during variant calling.  It is designed to be called as a step in a workflow or manually if needed.

This tool needs to produce VCF uploads that conform to the PanCancer VCF upload spec, see https://wiki.oicr.on.ca/display/PANCANCER/PCAWG+VCF+Submission+SOP+-+v1.0

## Dependencies

You can use PerlBrew (or your native package manager) to install dependencies.  For example:

    cpanm XML::DOM XML::XPath XML::XPath::XMLParser JSON Data::UUID XML::LibXML Time::Piece

Or on an Ubuntu 12.04 host you would install via:

    sudo apt-get install libxml-dom-perl libxml-xpath-perl libjson-perl libxml-libxml-perl

Once these are installed you can execute the script with the command below. For workflows and VMs used in the project, these dependencies will be pre-installed on the VM running the variant calling workflows.

You also need the gtdownload/gtuplod/cgsubmit tools installed.  These are available on the CGHub site and are only available for Linux (for the submission tools).

TODO: Sheldon, you'll want to have a dependency on VCF validation tool(s).

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

## Running

The parameters:

    perl gnos_upload_vcf.pl
       --metadata-urls <URLs_for_specimen-level_aligned_BAM_input_comma_sep>
       --vcfs <sample-level_vcf_file_path_comma_sep_if_multiple>
       --vcf-md5sum-files <file_with_vcf_md5sum_comma_sep_same_order_as_vcfs>
       --vcf-idxs <sample-level_vcf_idx_file_path_comma_sep_if_multiple>
       --vcf-idx-md5sum-files <file_with_vcf_idx_md5sum_comma_sep_same_order_as_vcfs>
       --tarballs <tar.gz_non-vcf_files_comma_sep_if_multiple>
       --tarball-md5sum-files <file_with_tarball_md5sum_comma_sep_same_order_as_tarball>
       --outdir <output_dir>
       --key <gnos.pem>
       --upload-url <gnos_server_url>
       [--workflow-src-url <http://... the source repo>]
       [--workflow-url <http://... the packaged SeqWare Zip>]
       [--workflow-name <workflow_name>]
       [--workflow-version <workflow_version>]
       [--seqware-version <seqware_version_workflow_compiled_with>]
       [--description-file <file_path_for_description_txt>]
       [--study-refname-override <study_refname_override>]
       [--analysis-center-override <analysis_center_override>]
       [--pipeline-json <pipeline_json_file>]
       [--qc-metrics-json <qc_metrics_json_file>]
       [--timing-metrics-json <timing_metrics_json_file>]
       [--make-runxml]
       [--make-expxml]
       [--force-copy]
       [--skip-validate]
       [--skip-upload]
       [--test]

An example for the files that have been checked in along with this code:

    cd sample_files
    perl ../gnos_upload_vcf.pl \
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

For the TCGA samples (which are most of the 60) this should be “tcga_pancancer_vcf_test”.  For the ICGC samples its “icgc_pancancer_vcf_test”.  Given the churn that happened last time with the alignment workflow I think it makes sense to keep the 60 in the “test” studies and switch over to the real one once the full set of donors are running.

## To Do

* removed hard coded XML files and replace with Template Toolkit templates (or something similar)
* need to add support for runtime and qc information files in a generic way (JSON file?)
* support for ".tbi" extensions rather than ".idx" (GNOS issue, would have be resolved by Annai on each GNOS server)
* validation needs to be implemented:
    * need to make sure each file conforms to the naming convention
    * need to ensure the headers (and contents) of VCF conform to the upload SOP, see https://wiki.oicr.on.ca/display/PANCANCER/PCAWG+VCF+Submission+SOP+-+v1.0
    * need to run the VCF files through VCFTools validation
* if not provided as files/params, compute the md5sums for the submitted files

## Bugs

The following items will need to be addressed by various parties:

* Annai: https://jira.oicr.on.ca/browse/PANCANCER-113
* Annai: https://jira.oicr.on.ca/browse/PANCANCER-114
