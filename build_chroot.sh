#!/bin/bash
#
# (c) Copyright by Wolfgang Fuschlberger
#
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#    ( http://www.fsf.org/licenses/gpl.txt )
#####################################################################

#
# if you need ping (for testing):
#
# chown root:root bin/ping; chmod u+srwx,go=rx bin/ping
#
# Under Linux, ping needs to run as root (because it needs to bind a raw IP socket; ordinary users can only do UDP and TCP). It's designed to be setuid root.
# RE: http://superuser.com/questions/284381/ping-not-working-in-a-chroot
#

#while getopts a:u:p:s:c:f option
#do
#case "${option}"
#in
#a) ACTION=${OPTARG};;
#u) USER=${OPTARG};;
#p) PASSWROD=${OPTARG};;
#s) SHELL=${OPTARG};;
#c) CHROOT=${OPTARG};;
#f) APPS=${OPTARG};;
#esac
#done

#case $ACTION in
#    initchroot) echo "$ACTION";;
#    removechroot) echo "$ACTION";;
#    jailuser) echo "$ACTION";;
#    freeuser) echo "$ACTION";;
#    deleuser) echo "$ACTION";;
#    update) echo "$ACTION";;
#esac



#echo -e "exiting"
#exit 1

# first Release: 2004-07-30
RELEASE="2008-04-26"
NOW=$(date +"%m-%d-%Y.%s")


#
# The latest version of the script is available at
#   http://www.fuschlberger.net/programs/ssh-scp-sftp-chroot-jail/
#
# Feedback is welcome!
#
# Thanks for Bugfixes / Enhancements to 
# Michael Prokop <http://www.michael-prokop.at/chroot/>,
# Randy K., Randy D., Jonathan Hunter and everybody else.
#####################################################################

#
# Features:
# - enable scp and sftp in the chroot-jail
# - use one directory (default /var/chroot/) as chroot for all users
# - create new accounts
# - move existing accounts to chroot
#####################################################################

# 
# Modified by pmenhart/Benbria:
# - work on Ubuntu 8.04
# - added APPS: cat more less nano
# - copy /lib/terminfo
# - made the script non-interactive
# -- create user without a password
# -- if the user exists and jailed then do nothing
# -- if the user exists then jail her
# -- do not create shell if already exists
#
# Original: http://www.devcu.com/forums/topic/560-chrootjail-users-for-sshscp-ubuntu-1204/
# Based on http://www.fuschlberger.net/programs/ssh-scp-sftp-chroot-jail/
#####################################################################

#
# Modifiied by jackofalltrades78:
# - added APPS: git svn mysql
#
# - TESTED on Ubuntu 12.04 LTS
# Forked from: https://github.com/pmenhart/make_chroot_jail
#

# path to sshd's config file: needed for automatic detection of the locaten of
# the sftp-server binary
SSHD_CONFIG="/etc/ssh/sshd_config"

# Check if we are called with username or update
if [ -z "$1" ] ; then
  echo
  echo "ERROR: Parameter missing. Did you forget the username?"
  echo "-------------------------------------------------------------"
  echo
  echo "USAGE:"
  echo "Create new chrooted account or"
  echo "add existing User to chroot-jail:"
  echo "-> $0 username"
  echo
  echo "or specify the chroot-shell file and path where the jail should be located:"
  echo "-> $0 username [/path/to/chroot-shell [/path/to/jail]]"
  echo "Default shell       = /bin/chroot-shell"
  echo "Default chroot-path = /var/chroot"
  echo "-------------------------------------------------------------"
  echo
  echo "Updating files in the chroot-jail:"
  echo "-> $0 update [/path/to/chroot-shell [/path/to/jail]]"
  echo "-------------------------------------------------------------"
  echo
  echo "To uninstall:"
  echo " # userdel \$USER"
  echo " # rm -rf /var/chroot"
  echo " (this deletes all Users' files!)"
  echo " # rm -f /bin/chroot-shell"
  echo " manually delete the User's line from /etc/sudoers"
  echo " or delete the username form /etc/sudoers.d/"
  exit
fi

if [ -z "$PATH" ] ; then 
  PATH=/bin:/usr/bin:/usr/local/bin:/sbin:/usr/sbin
fi

echo
echo $0 Release: $RELEASE
echo

if [ "$(whoami &2>/dev/null)" != "root" ] && [ "$(id -un &2>/dev/null)" != "root" ] ; then
  echo "Error: You must be root to run this script."
  exit 1
fi

# Check existence of necessary files
echo "Checking distribution... "
if [ -f /etc/debian_version ];
  then echo -n "  Supported Distribution found:"
       echo "  System is running Debian Linux"
       DISTRO=DEBIAN;
       ### Check Ubuntu version (e.g. hardy, precise)
       UBUNTU_CODENAME=`lsb_release -c | cut -f 2`
elif [ -f /etc/SuSE-release ];
  then echo "  Supported Distribution found"
       echo "  System is running SuSE Linux"
       DISTRO=SUSE;
elif [ -f /etc/fedora-release ];
  then echo "  Supported Distribution found"
       echo "  System is running Fedora Linux"
       DISTRO=FEDORA;
elif [ -f /etc/redhat-release ];
  then echo "  Supported Distribution found"
       echo "  System is running Red Hat Linux"
       DISTRO=REDHAT;
else echo -e "  failed...........\nThis script works best on Debian, Red Hat, Fedora and SuSE Linux!\n"
exit 1
fi

# Specify the apps you want to copy to the jail
if [ "$DISTRO" = SUSE ]; then
  APPS="/usr/bin/vim /bin/bash /bin/cp /usr/bin/dircolors /usr/bin/clear /bin/ls /bin/mkdir /bin/mv /bin/rm /bin/rmdir /bin/sh /bin/su /usr/bin/groups /usr/bin/id /usr/bin/netcat /usr/bin/rsync /usr/bin/ssh /usr/bin/scp /sbin/unix_chkpwd /usr/bin/git /usr/bin/svn /usr/bin/mysql /usr/bin/curl"
elif [ "$DISTRO" = FEDORA ]; then
  APPS="/usr/bin/vim /bin/bash /bin/cp /usr/bin/dircolors /usr/bin/clear /bin/ls /bin/mkdir /bin/mv /bin/rm /bin/rmdir /bin/sh /bin/su /usr/bin/groups /usr/bin/id /usr/bin/nc /usr/bin/rsync /usr/bin/ssh /usr/bin/scp /sbin/unix_chkpwd /usr/bin/git /usr/bin/svn /usr/bin/mysql /usr/bin/curl"
elif [ "$DISTRO" = REDHAT ]; then
  APPS="/usr/bin/vim /bin/bash /bin/cp /usr/bin/dircolors /usr/bin/clear /bin/ls /bin/mkdir /bin/mv /bin/rm /bin/rmdir /bin/sh /bin/su /usr/bin/groups /usr/bin/id /usr/bin/nc /usr/bin/rsync /usr/bin/ssh /usr/bin/scp /sbin/unix_chkpwd /usr/bin/git /usr/bin/svn /usr/bin/mysql /usr/bin/curl"
elif [ "$DISTRO" = DEBIAN ]; then
  APPS="/usr/bin/vim /bin/bash /bin/cp /usr/bin/dircolors /usr/bin/clear /bin/ls /bin/mkdir /bin/mv /bin/rm /bin/rmdir /bin/sh /bin/su /usr/bin/groups /usr/bin/id /usr/bin/rsync /usr/bin/ssh /usr/bin/scp /sbin/unix_chkpwd /bin/cat /bin/more /usr/bin/less /usr/bin/nano /usr/bin/git /usr/bin/svn /usr/bin/mysql /usr/bin/curl"
else
  APPS="/usr/bin/vim /bin/bash /bin/cp /usr/bin/dircolors /usr/bin/clear /bin/ls /bin/mkdir /bin/mv /bin/rm /bin/rmdir /bin/sh /bin/su /usr/bin/groups /usr/bin/id /usr/bin/rsync /usr/bin/ssh /usr/bin/scp /usr/sbin/unix_chkpwd /usr/bin/git /usr/bin/svn /usr/bin/mysql /usr/bin/curl"
fi

# Check existence of necessary files
echo -n "Checking for which... "
#if [ -f $(which which) ] ;
# not good because if which does not exist I look for an 
# empty filename and get OK nevertheless
if ( test -f /usr/bin/which ) || ( test -f /bin/which ) || ( test -f /sbin/which ) || ( test -f /usr/sbin/which );
  then echo "  OK";
  else echo "  failed

Please install which-binary!
"
exit 1
fi

echo -n "Checking for chroot..."
if [ `which chroot` ];
  then echo "  OK";
  else echo "  failed

chroot not found!
Please install chroot-package/binary!
"
exit 1
fi

echo -n "Checking for sudo..."
if [ `which sudo` ]; then
  echo "  OK";
else 
  echo "  failed

sudo not found!
Please install sudo-package/binary!
"
exit 1
fi

echo -n "Checking for dirname..."
if [ `which dirname` ]; then
  echo "  OK";
else 
  echo "  failed

dirname not found!
Please install dirname-binary (to be found eg in the package coreutils)!
"
exit 1
fi

echo -n "Checking for awk..."
if [ `which awk` ]; then
  echo "  OK
";
else 
  echo "  failed

awk not found!
Please install (g)awk-package/binary!
"
exit 1
fi

# get location of sftp-server binary from /etc/ssh/sshd_config
# check for existence of /etc/ssh/sshd_config and for
# (uncommented) line with sftp-server filename. If neither exists, just skip
# this step and continue without sftp-server
#
#if  (test ! -f /etc/ssh/sshd_config &> /dev/null); then
#  echo "
#File /etc/ssh/sshd_config not found.
#Not checking for path to sftp-server.
#  ";
#else
if [ ! -f ${SSHD_CONFIG} ]
then
   echo "File ${SSHD_CONFIG} not found."
   echo "Not checking for path to sftp-server."
   echo "Please adjust the global \$SSHD_CONFIG variable"
else
  if !(grep -v "^#" ${SSHD_CONFIG} | grep -i sftp-server &> /dev/null); then
    echo "Obviously no sftp-server is running on this system.
";
  else SFTP_SERVER=$(grep -v "^#" ${SSHD_CONFIG} | grep -i sftp-server | awk  '{ print $3}')
  fi
fi

#if !(grep -v "^#" /etc/ssh/sshd_config | grep -i sftp-server /etc/ssh/sshd_config | awk  '{ print $3}' &> /dev/null); then
APPS="$APPS $SFTP_SERVER"

# Get accountname to create / move
CHROOT_USERNAME=$1

if ! [ -z "$2" ] ; then
  SHELL=$2
else
  SHELL=/bin/chroot-shell
fi

if ! [ -z "$3" ] ; then
  JAILPATH=$3
else
  JAILPATH=/var/chroot
fi

# Exit if user already exists
#id $CHROOT_USERNAME > /dev/null 2>&1 && { echo "User exists."; echo "Exiting."; exit 1; }

# Check if user already exists and ask for confirmation
# we have to trust that root knows what she is doing when saying 'yes'
if ( id $CHROOT_USERNAME > /dev/null 2>&1 ) ; then {
  echo -n "User $CHROOT_USERNAME exists. "
  if [ -d $JAILPATH/users/$CHROOT_USERNAME ] ; then
    echo "Already jailed. Exiting...."
    exit 1
  fi
  echo "Adding the user to jail."
  MODIFYUSER="yes"
}
else
  CREATEUSER="yes"
fi

# Create $SHELL (shell for jailed accounts)
if [ -f ${SHELL} ] ; then
  echo "The file $SHELL already exists."
else
  echo "Creating $SHELL"
  echo '#!/bin/sh' > $SHELL
  echo "`which sudo` `which chroot` $JAILPATH /bin/su - \$USER" \"\$@\" >> $SHELL
  chmod 755 $SHELL
  cp $SHELL $JAILPATH$SHELL
fi

# make common jail for everybody if inexistent
if [ ! -d ${JAILPATH} ] ; then
  mkdir -p ${JAILPATH}
  echo "Creating ${JAILPATH}"
fi
cd ${JAILPATH}

# Create directories in jail that do not exist yet
JAILDIRS="dev etc etc/pam.d bin users sbin usr usr/bin usr/lib"
for directory in $JAILDIRS ; do
  if [ ! -d "$JAILPATH/$directory" ] ; then
    mkdir $JAILPATH/"$directory"
    echo "Creating $JAILPATH/$directory"
  fi
done
echo

# Comment in the following lines if your apache can't read the directories and
# uses the security contexts
# Fix security contexts so Apache can read files
#CHCON=$(`which chcon`)
#if [ -n "$CHCON" ] && [ -x $CHCON ]; then
#    $CHCON -t home_root_t $JAILPATH/home
#    $CHCON -t user_home_dir_t $JAILPATH/home/$CHROOT_USERNAME
#fi

# Creating necessary devices
# /dev/random was needed for git
[ -r $JAILPATH/dev/random ] || mknod $JAILPATH/dev/random c 1 8
[ -r $JAILPATH/dev/urandom ] || mknod $JAILPATH/dev/urandom c 1 9
[ -r $JAILPATH/dev/null ]    || mknod -m 666 $JAILPATH/dev/null    c 1 3
[ -r $JAILPATH/dev/zero ]    || mknod -m 666 $JAILPATH/dev/zero    c 1 5
[ -r $JAILPATH/dev/tty ]     || mknod -m 666 $JAILPATH/dev/tty     c 5 0 

# if we only want to update the files in the jail
# skip the creation of the new account
if [ "$1" != "update" ]; then

# Modifiy /etc/sudoers to enable chroot-ing for users
# must be removed by hand if account is deleted

if [ -d /etc/sudoers.d ]; then
  echo "Using /etc/sudoers.d/"
  echo "$CHROOT_USERNAME       ALL=NOPASSWD: `which chroot`, /bin/su - $CHROOT_USERNAME" > /etc/sudoers.d/$CHROOT_USERNAME
  chmod 0440 /etc/sudoers.d/$CHROOT_USERNAME
else
  echo "Modifying /etc/sudoers"  
  echo "Backing up /etc/sudoers"
  cp /etc/sudoers /etc/sudoers.$NOW
  echo "$CHROOT_USERNAME       ALL=NOPASSWD: `which chroot`, /bin/su - $CHROOT_USERNAME" >> /etc/sudoers
fi

# Define HomeDir for simple referencing
HOMEDIR="$JAILPATH/users/$CHROOT_USERNAME"

# Create new account, setting $SHELL to the above created script and
# $HOME to $JAILPATH/home/*
if [ "$CREATEUSER" != "yes" ] ; then echo "
Not creating new User account
Modifying User \"$CHROOT_USERNAME\" 
Copying files in $CHROOT_USERNAME's \$HOME to \"$HOMEDIR\"
"
usermod -d "$HOMEDIR" -m -s "$SHELL" $CHROOT_USERNAME && chmod 700 "$HOMEDIR"
fi

if [ "$CREATEUSER" = "yes" ] ; then {
echo "Adding User \"$CHROOT_USERNAME\" to system (no password)"
useradd -m -d "$HOMEDIR" -s "$SHELL" $CHROOT_USERNAME && chmod 700 "$HOMEDIR"

echo
}
fi

# Create /usr/bin/groups in the jail
echo "#!/bin/bash" > usr/bin/groups
echo "id -Gn" >> usr/bin/groups
chmod 755 usr/bin/groups

# Add users to etc/passwd
#
# check if file exists (ie we are not called for the first time)
# if yes skip root's entry and do not overwrite the file
if [ ! -f etc/passwd ] ; then
 grep /etc/passwd -e "^root" > ${JAILPATH}/etc/passwd
fi
if [ ! -f etc/group ] ; then
 grep /etc/group -e "^root" > ${JAILPATH}/etc/group
# add the group for all users to etc/group (otherwise there is a nasty error
# message and probably because of that changing directories doesn't work with
# winSCP)
 grep /etc/group -e "^users" >> ${JAILPATH}/etc/group
fi

# grep the username which was given to us from /etc/passwd and add it
# to ./etc/passwd replacing the $HOME with the directory as it will then 
# appear in the jail
echo "Adding User $CHROOT_USERNAME to jail"
grep -e "^$CHROOT_USERNAME:" /etc/passwd | \
 sed -e "s#$JAILPATH##"      \
     -e "s#$SHELL#/bin/bash#"  >> ${JAILPATH}/etc/passwd

# if the system uses one account/one group we write the
# account's group to etc/group
grep -e "^$CHROOT_USERNAME:" /etc/group >> ${JAILPATH}/etc/group

# write the user's line from /etc/shadow to /var/chroot/etc/shadow
grep -e "^$CHROOT_USERNAME:" /etc/shadow >> ${JAILPATH}/etc/shadow
chmod 600 ${JAILPATH}/etc/shadow

# endif for =! update
fi

# Copy the apps and the related libs
echo "Copying necessary library-files to jail (may take some time)"

# The original code worked fine on RedHat 7.3, but did not on FC3.
# On FC3, when the 'ldd' is done, there is a 'linux-gate.so.1' that 
# points to nothing (or a 90xb.....), and it also does not pick up
# some files that start with a '/'. To fix this, I am doing the ldd
# to a file called ldlist, then going back into the file and pulling
# out the libs that start with '/'
# 
# Randy K.
#
# The original code worked fine on 2.4 kernel systems. Kernel 2.6
# introduced an internal library called 'linux-gate.so.1'. This 
# 'phantom' library caused non-critical errors to display during the 
# copy since the file does not actually exist on the file system. 
# To fix re-direct output of ldd to a file, parse the file and get 
# library files that start with /
#

# create temporary files with mktemp, if that doesn't work for some reason use
# the old method with $HOME/ldlist[2] (so I don't have to check the existence
# of the mktemp package / binary at the beginning
#
TMPFILE1=`mktemp` ||  TMPFILE1="${HOME}/ldlist"; if [ -x ${TMPFILE1} ]; then mv ${TMPFILE1} ${TMPFILE1}.bak;fi
TMPFILE2=`mktemp` ||  TMPFILE2="${HOME}/ldlist2"; if [ -x ${TMPFILE2} ]; then mv ${TMPFILE2} ${TMPFILE2}.bak;fi

for app in $APPS;  do
    # First of all, check that this application exists
    if [ -x $app ]; then
        # Check that the directory exists; create it if not.
#        app_path=`echo $app | sed -e 's#\(.\+\)/[^/]\+#\1#'`
        app_path=`dirname $app`
        if ! [ -d .$app_path ]; then
            mkdir -p .$app_path
        fi

		# If the files in the chroot are on the same file system as the
		# original files you should be able to use hard links instead of
		# copying the files, too. Symbolic links cannot be used, because the
		# original files are outside the chroot.
		cp -p $app .$app

        # get list of necessary libraries
        ldd $app >> ${TMPFILE1}
    fi
done

# Clear out any old temporary file before we start
for libs in `cat ${TMPFILE1}`; do
   frst_char="`echo $libs | cut -c1`"
   if [ "\"$frst_char\"" = "\"/\"" ]; then
     echo "$libs" >> ${TMPFILE2}
   fi
done
for lib in `cat ${TMPFILE2}`; do
    mkdir -p .`dirname $lib` > /dev/null 2>&1

	# If the files in the chroot are on the same file system as the original
	# files you should be able to use hard links instead of copying the files,
	# too. Symbolic links cannot be used, because the original files are
	# outside the chroot.
    cp $lib .$lib
done

#
# Now, cleanup the 2 files we created for the library list
#
#/bin/rm -f ${HOME}/ldlist
#/bin/rm -f ${HOME}/ldlist2
/bin/rm -f ${TMPFILE1}
/bin/rm -f ${TMPFILE2}

# Necessary files that are not listed by ldd.
#
# There might be errors because of files that do not exist but in the end it
# may work nevertheless (I added new file names at the end without deleting old
# ones for reasons of backward compatibility).
# So please test ssh/scp before reporting a bug.
if [ "$DISTRO" = SUSE ]; then
  cp /lib/libnss_compat.so.2 /lib/libnss_files.so.2 /lib/libnss_dns.so.2 /lib/libxcrypt.so.1 ${JAILPATH}/lib/
elif [ "$DISTRO" = FEDORA ]; then
  cp /lib/libnss_compat.so.2 /lib/libnsl.so.1 /lib/libnss_files.so.2 /lib/ld-linux.so.2 /lib/ld-ldb.so.3 /lib/ld-lsb.so.3 /lib/libnss_dns.so.2 /lib/libxcrypt.so.1 ${JAILPATH}/lib/
  cp /lib/*.* ${JAILPATH}/lib/
  cp /usr/lib/libcrack.so.2 ${JAILPATH}/usr/lib/
elif [ "$DISTRO" = REDHAT ]; then
  cp /lib/libnss_compat.so.2 /lib/libnsl.so.1 /lib/libnss_files.so.2 /lib/ld-linux.so.2 /lib/ld-lsb.so.1 /lib/libnss_dns.so.2 /lib/libxcrypt.so.1 ${JAILPATH}/lib/
  # needed for scp on RHEL
  echo "export LD_LIBRARY_PATH=/usr/kerberos/lib" >> ${JAILPATH}/etc/profile
elif [ "$DISTRO" = DEBIAN ]; then
  if [ "$UBUNTU_CODENAME" = "hardy" ]; then
    cp /lib/libnss_compat.so.2 /lib/libnsl.so.1 /lib/libnss_files.so.2 /lib/libcap.so.1 /lib/libnss_dns.so.2 ${JAILPATH}/lib/
  else
    cp /lib/x86_64-linux-gnu/libnss_compat.so.2 /lib/x86_64-linux-gnu/libnsl.so.1 /lib/x86_64-linux-gnu/libnss_files.so.2 /lib/x86_64-linux-gnu/libcap.so.2 /lib/x86_64-linux-gnu/libnss_dns.so.2 ${JAILPATH}/lib/
  fi
  # needed for less and nano and clear
  cp -ar /lib/terminfo ${JAILPATH}/lib/
else
  cp /lib/libnss_compat.so.2 /lib/libnsl.so.1 /lib/libnss_files.so.2 /lib/libcap.so.1 /lib/libnss_dns.so.2 ${JAILPATH}/lib/
fi

# if you are using a 64 bit system and have strange problems with login comment
# the following lines in, perhaps it works then (motto: if you can't find the
# needed library just copy all of them)
#
#cp /lib/*.* ${JAILPATH}/lib/
#cp /lib/lib64/*.* ${JAILPATH}/lib/lib64/ 

# if you are using PAM you need stuff from /etc/pam.d/ in the jail,
echo "Copying files from /etc/pam.d/ to jail"
cp /etc/pam.d/* ${JAILPATH}/etc/pam.d/

# ...and of course the PAM-modules...
echo "Copying PAM-Modules to jail"
cp -r /lib/x86_64-linux-gnu/security ${JAILPATH}/lib/
# this is needed for Ubuntu 8.04, but will not hurt on 12.04 neither
if [ -d /lib/security ] ; then
  cp -r /lib/security ${JAILPATH}/lib/
fi
# ...and something else useful for PAM
cp -r /etc/security ${JAILPATH}/etc/
cp /etc/login.defs ${JAILPATH}/etc/

if [ -f /etc/DIR_COLORS ] ; then
  cp /etc/DIR_COLORS ${JAILPATH}/etc/
fi 

# ...and required crap for git
if [ -d /usr/share/git-core ] ; then
  if [ ! -d ${JAILPATH}/usr/share ] ; then
    mkdir -p ${JAILPATH}/usr/share
  fi
  cp -pR /usr/share/git-core ${JAILPATH}/usr/share/
fi

if [ -d /usr/lib/git-core ] ; then
  if [ ! -d ${JAILPATH}/usr/lib ] ; then
    mkdir -p ${JAILPATH}/usr/lib
  fi
  cp -pR /usr/lib/git-core ${JAILPATH}/usr/lib/
fi

# required if curl is compiled with --with-gnutls
# ldd misses it and its reuired for git
if [ -d /usr/lib/x86_64-linux-gnu ] ; then
  if [ ! -d ${JAILPATH}/usr/lib/x86_64-linux-gnu ] ; then
    mkdir -p ${JAILPATH}/usr/lib/x86_64-linux-gnu
  fi
  cp -p /usr/lib/x86_64-linux-gnu/libcurl-gnutls* ${JAILPATH}/usr/lib/x86_64-linux-gnu/
fi

# and yet more shit to use git...
# SSL CA cert
if [ ! -f ${JAILPATH}/etc/ssl/certs/ca-certificates.crt ] ; then
  if [ ! -d ${JAILPATH}/etc/ssl/certs/ ] ; then 
    mkdir -p ${JAILPATH}/etc/ssl/certs
  fi
  cp -p /etc/ssl/certs/ca-certificates.crt ${JAILPATH}/etc/ssl/certs/
fi

# well we kinda need this if we need git or svn or scp or anything...
cp -p /etc/resolv.conf ${JAILPATH}/etc/
cp -p /etc/hosts ${JAILPATH}/etc/
# and this for svn
cp -p /etc/nsswitch.conf ${JAILPATH}/etc/nsswitch.conf
cp -p /etc/host.conf ${JAILPATH}/etc/host.conf

# Don't give more permissions than necessary
chown root.root ${JAILPATH}/bin/su
chmod 700 ${JAILPATH}/bin/su

exit

