#!/bin/bash

azure account show &> /dev/null
if [ $? -ne 0 ]
	then
	# We need to authenticate 
	azure login
fi
azure config mode arm &> /dev/null

if [ ! -z $1 ] 
then
	location=$1
else
	location="westus"
fi

echo "Getting the extensions available in $location datacenter.  This will take several minutes..."
echo ""
startSeconds=`date +%s` 

# Print all the extension publisher data for the datacenter, but only one header.  
echo "data:    Publisher   Type                   Version  Location"
echo "data:    ----------  ---------------------  -------  --------"

azure vm extension-image list-publishers -l $location | \
	awk -v loc="$location" '/data:/ {if ($3==loc) {system("azure vm extension-image list-types -l " $3 " -p " $2)}}' | \
	awk -v loc="$location" '/data:/ {if ($4==loc) {system("azure vm extension-image list-versions -l " $4 " -p " $2 " -t " $3)}}' | \
	awk -v loc="$location" '/data:/ {if ($5==loc) {print $0}}'
	

endSeconds=`date +%s`
duration=$(($endSeconds-$startSeconds))
echo "Script duration: $duration seconds"