# README

## Overview

This tool is designed to upload one or more VCF/tar.gz/index files produced during variant calling.  It is designed to be called as a step in a workflow or manually if needed.

This tool needs to produce VCF uploads that conform to the PanCancer VCF upload spect, see https://wiki.oicr.on.ca/display/PANCANCER/PCAWG+VCF+Submission+SOP+-+v1.0

## Dependencies

You can use PerlBrew (or your native package manager) to install dependencies.  For example:

    cpanm XML::DOM XML::XPath XML::XPath::XMLParser JSON Data::UUID XML::LibXML Time::Piece

Once these are installed you can execute the script with the command below. For workflows and VMs used in the project, these dependencies will be pre-installed on the VM running the variant calling workflows.

You also need the gtdownload/gtuplod/cgsubmit tools installed.  These are available on the CGHub site and are only available for Linux (for the submission tools).

## Inputs

The variant calling working group has established naming conventions for the files submitted from variant calling workflows.  See https://wiki.oicr.on.ca/display/PANCANCER/PCAWG+file+formats+and+naming+conventions and the SOP https://wiki.oicr.on.ca/display/PANCANCER/VCF+Upload+SOP.

This tool is designed to work with the following file types:

* vcf.gz: VCF file http://samtools.github.io/hts-specs/VCFv4.2.pdf compressed with 'bgzip <filename.vcf>', see http://vcftools.sourceforge.net/perl_module.html
* vcf.gz.idx: tabix index generated with 'tabix -p vcf foo.vcf.gz; mv foo.vcf.gz.tbi foo.vcf.gz.idx'
* vcf.gz.md5: md5sum file made with 'md5sum foo.vcf.gz | awk '{print$1}' > foo.vcf.gz.md5'
* vcf.gz.idx.md5: md5sum file make with 'md5sum foo.vcf.gz.idx | awk '{print$1}' > foo.vcf.gz.idx.md5'

And we also have a generic container format for files other than VCF/IDX file types:

* tar.gz: a standard tar/gz file format made with something similar to 'tar zcf bar.tar.gz <files>'. The tar.gz file must contain a README file that describes its contents
* tar.gz.md5: md5sum file made with something like 'md5sum bar.tar.gz | awk '{print$1}' > bar.tar.gz.md5'.

The files should be named using the following conventions:

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

There may be multiple somatic call files each with different Samples IDs if, for example, there is a cell-line, metastasis, second tumor sample.  There should be 0 or 1 germline file.

Note: the variant calling working group has specified ".tbi" rather than ".idx" as the tabix index extension. I have asked Annai to add support for ".tbi" and will update the code to standardize on this once the GNOS changes have been made.  Also, a README needs to be included in each tar.gz file to document the contents. In the pilot this was a separate README file but GNOS does not support uploading this directly and, therefore, it needs to included in the tar.gz file.

## Running

The parameters:

    perl gnos_upload_vcf.pl
       --metadata-url <URL_for_specimen-level_aligned_BAM_input>
       --vcfs <sample-level_vcf_file_path_comma_sep_if_multiple>
       --vcf-types <sample-level_vcf_file_types_comma_sep_if_multiple_same_order_as_vcfs>
       --vcf-md5sum-files <file_with_vcf_md5sum_comma_sep_same_order_as_vcfs>
       --vcf-idxs <sample-level_vcf_idx_file_path_comma_sep_if_multiple>
       --vcf-idx-md5sum-files <file_with_vcf_idx_md5sum_comma_sep_same_order_as_vcfs>
       --tarballs <tar.gz_non-vcf_files_comma_sep_if_multiple>
       --tarball-md5sum-files <file_with_tarball_md5sum_comma_sep_same_order_as_tarball>
       --tarball-types <sample-level_tarball_file_types_comma_sep_if_multiple_same_order_as_vcfs>
       --outdir <output_dir>
       --key <gnos.pem>
       --upload-url <gnos_server_url>
       [--suppress-runxml]
       [--suppress-expxml]
       [--force-copy]
       [--study-refname-override <study_refname_override>]
       [--analysis-center-override <analysis_center_override>]
       [--skip-validate]
       [--test]

An example for a germline VCF and a germline :

    perl  gnos_upload_vcf.pl --metadata-url https://gtrepo-osdc-icgc.annailabs.com/cghub/metadata/analysisFull/d1747d83-f0be-4eb1-859b-80985421a38e,https://gtrepo-osdc-icgc.annailabs.com/cghub/metadata/analysisFull/97146325-910b-48ae-8f4d-c2ae976b3087 \
    --metadata-url-types normal,tumor
    --vcfs 914ee592-e855-43d3-8767-a96eb6d1f067.TestWorkflow_1-0-0.20141009.germline.vcf.gz \
    --vcf-types germline \
    --vcf-md5sum-files 914ee592-e855-43d3-8767-a96eb6d1f067.TestWorkflow_1-0-0.20141009.germline.vcf.gz.md5 \
    --vcf-idxs 914ee592-e855-43d3-8767-a96eb6d1f067.TestWorkflow_1-0-0.20141009.germline.vcf.gz.idx \
    --vcf-idx-md5sum-files 914ee592-e855-43d3-8767-a96eb6d1f067.TestWorkflow_1-0-0.20141009.germline.vcf.gz.idx.md5 \
    --tarballs 914ee592-e855-43d3-8767-a96eb6d1f067.TestWorkflow_1-0-0.20141009.germline.tar.gz \
    --tarball-md5sum-files 914ee592-e855-43d3-8767-a96eb6d1f067.TestWorkflow_1-0-0.20141009.germline.tar.gz.md5 \
    --tarball-types germline --outdir test --key test.pem \
    --upload-url https://gtrepo-ebi.annailabs.com \
    --study-refname-override icgc_pancancer_vcf_test --test

Something to note from the above, you'll want to

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

## To Do

* probably a good idea to unify this code with the BAM uploader to reduce code duplication
* need to add params for various hard-coded items below so the same script can be used for multiple variant workflows. For example workflow name, version, etc
* the description needs details about the files produced by the workflow, naming conventions, etc
* need a key-value attribute that documents each VCF/tarball file, what specimens they contain, the variant types they contain, etc.
* removed hard coded files and replace with templates
* support .gz vcf files, perhaps always make these if input is .vcf?
* need to add support for runtime and qc information files in a generic way
* support for ".tbi" extensions rather than ".idx"
* add code to test for gtupload/gtsubmit
* MAJOR: need to be able to support mulitple --metadata-url for, example, the somatic calls will combine the normal and tumor aligned BAMs
* MAJOR: currently you'll need to run the tool twice, once for germline upload and the second for somatic.  You can't mix the two otherwise you'll have an analysis that has a bunch of GNOS XML attributes from both.  The URL can be a comma seperated list, so should make sure I create a single analysis.xml for all submission files that correctly labels the various bits of the XML so that it's easy to tell what came from where.  The key is a single analysis.xml submission for a given workflow run so that way it's easy to tell the difference between different runs of the workflow.  You could still call the tool multiple times to give somatic/germline different analysis.xml and entries in the GNOS.  But it's better to have everything in one analysis ID on the server.
* we need a way to pass in a JSON that describes the steps of the workflow
* what about the "--metadata-url-types normal,tumor" parameter, what's going on with this?  What controlled vocab to use here?

## Bugs

The following items will need to be addressed by various parties:

* Annai: https://jira.oicr.on.ca/browse/PANCANCER-113
* Annai: https://jira.oicr.on.ca/browse/PANCANCER-114
