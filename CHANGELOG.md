# 2.0.7

udpated the gt-download-upload-wrapper to version 2.0.13
* added minimal transfer speed param for download
* added final check for "100%" in the upload log before calling upload complete in order to catch situations where an upload isn't actually finished

# 2.0.6

* Added the following parameters to the `gnos_download_file.pl` script. If not specified the default for `gtdownload` will be used:
  * --max-children <gtdownload_default>
  * --rate-limit-mbytes <gtdownload_default>
  * --k-timeout <minutes_of_inactivity_to_abort_recommend_less_than_timeout_if_you_want_this_to_be_used>
* Previously the values were hard coded to: 4, 200, and 60 respectively, if you want to match the old behavior you must specify these values otherwise the defaults for gtdownload will be used, see [here](https://cghub.ucsc.edu/docs/user/CGHubUserGuide.pdf).
* Added optional param `k-timeout-min` to `gnos_upload_vcf.pl`, defaults to 60. This is passed to gtupload as the `-k` param.

# 2.0.5

* checking if the pem key path exists
* number of arguments checking relaxed, help is displayed with `--help` or no arguments
* option to specify either VCF or tar, one is required but not both
* added optional parameters that specify UUIDs for related GNOS uploads
* updated docs
