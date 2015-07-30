#!/usr/bin/env perl

use warnings;
use strict;

use feature qw(say);

use autodie;

use Getopt::Long;

use GNOS::Download;

# Example Command:
# cd /mnt/seqware-oozie/23f5253a-f33b-11e3-8add-8589c49f5d8e
# perl /mnt/home/seqware/git/genomic_tools/gnos_tools/launch_and_monitor_gnos.pl --command 'gtdownload --max-children 4 --rate-limit 200 -c /home/seqware/provisioned-bundles/Workflow_Bundle_BWA_2.6.3_SeqWare_1.1.0-alpha.5/Workflow_Bundle_BWA/2.6.3/scripts/gnostest.pem -v -d https://gtrepo-dkfz.annailabs.com/cghub/data/analysis/download/23f5253a-f33b-11e3-8add-8589c49f5d8e' --file-grep 23f5253a-f33b-11e3-8add-8589c49f5d8e --search-path . --md5-retries 120 --retries 30
### setup / INSTALL
# mkdir /mnt/seqware-oozie/23f5253a-f33b-11e3-8add-8589c49f5d8e
# sudo apt-get install libcommon-sense-perl
# PURPOSE:
# the program takes a command (use single quotes to encapsulate it in bash) and
# a to check, the existance of which indidates the gtdownload finished running.
# It also takes a retries count, timeout for no data being written in minutes, and a
# cooldown (sleep) time in minutes for checking if the output exists. It then executes the command in a thread and
# watches the files every sleep time. For every timeout period where there is no
# change in the output file size then the retries count is
# decremented. By default, the retries are 30 and timeout 60 minutes so the code
# could retry a download that times out a total of 30 hours before giving up.
# If the retries are exhausted the thread is killed, the
# thread is recreated and started, and the process starts over.

# where file is the GNOS id of the file

my ($pem, $url, $file);
my $timeout_min = 60;
my $retries = 30;
my $max_children = 0;
my $rate_limit_mbytes = 0;
my $k_timeout_min = 0;

if (scalar(@ARGV) == 0) {
  die "USAGE: $0 --pem <pem_path> --url <download_gnos_url> --file <output_file_to_check> [--retries 30] [--timeout-min 60] [--max-children <gtdownload_default>] [--rate-limit-mbytes <gtdownload_default>] [--ktimeout <minutes_of_inactivity_to_abort_recommend_less_than_timeout_if_you_want_this_to_be_used>]\n";
}

GetOptions (
"pem=s" => \$pem,
"url=s" => \$url,
"file=s" => \$file,
"retries=i" => \$retries,
"timeout-min=i" => \$timeout_min,
"max-children=i" => \$max_children,
"rate-limit-mbytes=i" => \$rate_limit_mbytes,
"ktimeout=i" => \$k_timeout_min,
);

say "FILE: $file";

# will return 0 on success, not 0 on failure
my $ret_val = GNOS::Download->run_download($pem, $url, $file, $retries, $timeout_min, $max_children, $rate_limit_mbytes, $k_timeout_min);
exit ($ret_val);
