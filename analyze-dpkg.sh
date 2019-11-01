#/bin/bash!

# analyze-dpkg: Tool for sending all ELF files in packages 
# maintained for a Debian based Linux distribution (Ubuntu, Kali etc.) to 
# Intezer Analyze for analysis.

# Dependencies: apt-file ; curl 

# Notes:
		# 1. Run as sudo or root to minimize stalling loops
		# 2. KFILE needs to be a .json file with the following parameters:
#		 {
#				 "api_key": "<your API key>"
#		 }

# Request session Token

BASEURL='https://analyze.intezer.com/api/v2-0'
KFILE='apikey.json'

# Use API Key to get Token for session
curl -s \
		-d "@${KFILE}" \
		-H 'Content-Type: application/json' \
		${BASEURL}/get-access-token \
		| sed 's/{//; s/}//; s/"result"://; s/"//g' > token.txt

TOKEN=$(cat token.txt)

#Make directories to store extracted ELF files

mkdir ${PWD}/DYNrepo
mkdir ${PWD}/CORErepo
mkdir ${PWD}/EXECrepo
mkdir ${PWD}/RELrepo
mkdir ${PWD}/otherELF

DYNREPO="${PWD}/DYNrepo/"
COREREPO="${PWD}/CORErepo/"
EXECREPO="${PWD}/EXECrepo/"
RELREPO="${PWD}/RELrepo/"
OTHERREPO="${PWD}/otherELF/"

#List all available Debian standard repository packages
PACKLIST=$(apt-cache search . | sort | sed 's/ - .*//g')

echo " Log of file analysis for packages from repository" > repo-pkg.log
echo "ELF Type,Package,Filepath" > REL.log
echo "ELF Type,Package,Filepath" > EXEC.log
echo "ELF Type,Package,Filepath" > DYN.log
echo "ELF Type,Package,Filepath" > CORE.log
echo "ELF Type,Package,Filepath" > OTHER.log

#Function parameters: $1= ELF path	$2=Package Name
function elfsort() {
		local ESORT=$(readelf -h ${1} | grep 'Type:' | sed 's/  Type: *//; s/ (.*//')
		case ${ESORT} in
				DYN)
						echo "DYN,${2},${1}" >> DYN.log
						cp ${1} ${DYNREPO}
						;;
				CORE)
						echo "CORE,${2},${1}" >> CORE.log
						cp ${1} ${COREREPO}
						;;
				EXEC)
						echo "EXEC,${2},${1}" >> EXEC.log
						cp ${1} ${EXECREPO}
						;;
				REL)
						echo "REL,${2},${1}" >> REL.log
						cp ${1} ${RELREPO}
						;;
				*)
						echo "${ESORT},${2},${1}" >> OTHER.log
						cp ${1} ${OTHERREPO}
						;;
		esac
}

#Function paremeters: $1=package name $2=log filename
function analyze-send() {
		local PFLIST=$(apt-file list $1 | sed 's/'${1}'://')
		for IDELF in ${PFLIST}
		do
				#Check if file is an ELF
				readelf -h ${IDELF} &> /dev/null
				local ECHK=$(echo $?)

				if [ ${ECHK} -eq 0 ]
				then
						echo "${1}: ${IDELF}" >> $2  #Log Filename
						elfsort ${IDELF} ${1}
						curl -s -F "file=@${IDELF}" \
								-H "Authorization: Bearer ${TOKEN}" \
								${BASEURL}/analyze >> $2
				else
						echo "${IDELF}" >> /dev/null
				fi
		done
}

# Loop for installing packages, finding added executable files, 
# sending to analyze and removing package.

function repo-pkg-scan() {
		for PACK in ${PACKLIST}
		do
				#Checks if a package is already installed
				dpkg -s $PACK &> /dev/null
				local STPCHK=$(echo $?)
				if [ ${STPCHK} -eq 0 ]
				then
						# Send pre-installed package ELF files to Analyze
						analyze-send ${PACK} repo-pkg.log 
				else
						# Install package without user input
						sudo apt-get -yq install ${PACK} &> /dev/null

						# Send downloaded ELF files to Analyze
						analyze-send ${PACK} repo-pkg.log

						# Removes installed package
						sudo apt-get -yq remove --purge $PACK &> /dev/null
						sudo apt-get -yq autoremove &> /dev/null
				fi
		done
}

repo-pkg-scan
echo "Repository Scan Complete"
