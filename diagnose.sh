#!/bin/bash

samples=0
failures_gender=0
failures_diskspace=0
failures_xml_to_bas=0
failures_download=0
failures_ascat=0
failures_pindel=0
failures_memory=0

for dir in oozie*; do
	((samples++))
	echo ""
	echo "========================="
	echo "$dir" 
	echo "========================="
	check1=$(cat ./$dir/stdout.txt)
	echo ""
	[[ $1 == "verbose" ]] && cat ./$dir/stdout.txt
	echo "========================="
	check2=$(cat ./$dir/stderr.txt)
	[[ $1 == "verbose" ]] && cat ./$dir/stderr.txt 

	# Analysis
	count=""
	count=$(echo "$check1 $check2" | grep "Gender loci gacve incolclusive results")
	if [[ ! -z $count ]]; then
		echo "Failure due to ASCAT gender determination."	
		((failures_gender++))
	fi
	count=""
	count=$(echo "$check1 $check2" | grep "The system is running low on disk space.  Shutting down download client.")
        if [[ ! -z $count ]]; then
                echo "Failure due to lack of diskspace."       
       		((failures_diskspace++)) 
	fi 
	count=""
	count=$(echo "$check1 $check2" | grep "xml_to_bas.pl line 37.")
        if [[ ! -z $count ]]; then
                echo "Failure due to xml_to_bas execution: invalid JSON."       
		((failures_xml_to_bas++))
        fi 
	count=""
	count=$(echo "$check1 $check2" | grep "xml_to_bas.pl line 89.")
        if [[ ! -z $count ]]; then
                echo "Failure due to xml_to_bas execution: path problem or missing file problem."       
		((failures_xml_to_bas++))
        fi
	count=""
	count=$(echo "$check1 $check2" | grep "ERROR: Surpassed the number of retries: 10 with count 10, EXITING!!")
        if [[ ! -z $count ]]; then
                echo "Failure due to download execution."       
		((failures_download++))
        fi
	count=""
	count=$(echo "$check1 $check2" | grep "ERROR: THREAD NOT RUNNING BUT OUTPUT MISSING, RESTARTING THE THREAD!!" | wc -l)
        if [[ $count == "3" ]]; then
                echo "gtdownload thread failed multiples times!"       
                ((failures_download++))
        fi
	count=""
        count=$(echo "$check1 $check2" | grep "EXISTS AND THREAD EXITED NORMALLY, Total number of tries: 0")
        if [[ ! -z $count ]]; then
                echo "Download retry code used and succeeded."       
        fi
	count=""
        count=$(echo "$check1 $check2" | grep "Errors from command: /mnt/home/seqware/provisioned-bundles/Workflow_Bundle_SangerPancancerCgpCnIndelSnvStr_1.0.3_SeqWare_1.1.0-alpha.5/Workflow_Bundle_SangerPancancerCgpCnIndelSnvStr/1.0.3/bin/opt/bin/bgzip -c seqware-results/1/ascat/" )
        if [[ ! -z $count ]]; then
                echo "Failure due to ASCAT finalize problem on copy!"       
                ((failures_ascat++))
        fi
	count=""
        count=$(echo "$check1 $check2" | grep "Errors from command: /usr/bin/perl /mnt/home/seqware/provisioned-bundles/Workflow_Bundle_SangerPancancerCgpCnIndelSnvStr_1.0.3_SeqWare_1.1.0-alpha.5/Workflow_Bundle_SangerPancancerCgpCnIndelSnvStr/1.0.3/bin/opt/bin/pindel_2_combined_vcf.pl" )
        if [[ ! -z $count ]]; then
                echo "Failure due to pindel_2_combined_vcf.pl!"       
                ((failures_pindel++))
        fi
	count=""
        count=$(echo "$check1 $check2" | grep "alloc")
        if [[ ! -z $count ]]; then
                echo "Memory allocation problems!"       
                ((failures_memory++))
        fi

	echo "========================="
	[[ $1 != "nopause" ]] && read -p "Press ENTER for next sample"
	echo ""	

done
echo "Total Failures: $samples"
echo "Failures due to gender: $failures_gender"
echo "Failures due to diskspace: $failures_diskspace"
echo "Failures due to xml_to_bas: $failures_xml_to_bas"
echo "Failures due to download: $failures_download"
echo "Failures due to ascat: $failures_ascat"
echo "Failures due to memory allocation problems: $failures_memory"

