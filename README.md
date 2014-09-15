# README

## Overview

This tool is designed to upload one or more VCF/tarball files produced during variant calling.

This is a work in progress. See https://wiki.oicr.on.ca/display/PANCANCER/VCF+Upload+SOP for more information.

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
       [--force-copy]
       [--study-refname-override <study_refname_override>]
       [--analysis-center-override <analysis_center_override>]
       [--skip-validate]
       [--test]

An example:

    perl  gnos_upload_vcf.pl --metadata-url https://gtrepo-osdc-icgc.annailabs.com/cghub/metadata/analysisDetail/0480b9bb-611d-4759-a305-98f9298474fe --vcfs foo.vcf --vcf-types somatic --vcf-md5sum-files foo.vcf.md5 --vcf-idxs foo.vcf.idx --vcf-idx-md5sum-files foo.vcf.idx.md5 --tarballs bar.tar.gz --tarball-md5sum-files bar.tar.gz.md5 --tarball-types somatic --outdir test --key test.pem --upload-url https://gtrepo-osdc-icgc.annailabs.com --study-refname-override CGTEST --test
