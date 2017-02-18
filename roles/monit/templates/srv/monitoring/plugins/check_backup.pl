#!/usr/bin/env perl
#{{ ansible_managed }}

#===============================================================================
# Auteur : pihomecloud
# Date   : 08/11/2015
# But    : Vérification d'une liste de certificats et leur clé correspondante
#===============================================================================
use strict;
use warnings;
use Getopt::Long;
use POSIX qw(strftime);


my $VERSION = '1.0';

my ($ok, $warning, $critical, $unknown, $dependant) = (0,1,2,3,4);
my @statusName = ('OK', 'WARNING', 'CRITICAL', 'UNKNOWN', 'DEPENDANT');

my $status = $ok;
my $exitMessage = "";
my $messageSeparator = ",\n";
my $errorOnly;
my $summary = "";
my $logTime;


sub usage {
  my $message = shift;
  print $message."\n" if $message;
  print "Usage : $0 -d backupLogdir [-n logname] [-t max time of log modification in seconds]\n";
  exit $unknown;
}

sub status {
  my $tStatus = shift;
  # ok < warning < critical < unknown < dependant
  $status = $tStatus if $status < $tStatus;
}

sub finalExit {
  my $tStatus = shift;
  my $message = shift;
  my $timeMessage=" is from today";
  if ($logTime){
    $timeMessage="has less than ${logTime}s";
  }
 
  $summary = "Log seems complete, $timeMessage and no error found" unless $summary;
  status $tStatus if $tStatus;
  $exitMessage = "[".$statusName[$status]."] Check is ".$statusName[$status]." " unless $exitMessage;
  $exitMessage = "[".$statusName[$status]."] $summary$messageSeparator$exitMessage";
  $exitMessage.=$message if $message;
  print $exitMessage."\n";
  exit $status;
}

sub addMessage {
  my $tStatus = shift;
  my $message = join(' ', @_);
  status $tStatus;
  if ($tStatus > $ok or !$errorOnly){
    $summary .= $statusName[$tStatus].":".$message." ";
  }
  $exitMessage .= $messageSeparator if $exitMessage;
  $exitMessage .= "[".$statusName[$tStatus]."] ".$message;
}

my $file;
my $logDir;
my $logName;
my $verbose;
my $seemsTbeComplete;
my $lastCheck ="Backup finished";
GetOptions( 'logdir|d=s' =>\$logDir , 'logname|n=s' =>\$logName, 'time|t=i' =>\$logTime, 'error_only|e' => \$errorOnly, 'verbose|v' => \$verbose ) or usage "Invalid parameter";

usage "logdir is mandatory" unless $logDir;

if (! $logName){
  $file=`ls -tr $logDir 2>/dev/null| tail -1`;
  chomp $file;
  $file = $logDir.'/'.$file;
  $file =~ s/\/\//\//g;
}else{
  $file = $logDir.'/'.$logName;
}

if (! $logTime){
  my $day = strftime "+%Y%m%d", localtime;
  if($file =~ /.bck.$day/){
    addMessage $ok,"Backup file is from today";
  }else{
    addMessage $warning,"Backup file is not from today";
  }
}elsif (! -e $file){
  addMessage $critical,"Backup file $file no found !";
}else{
  my $logModification = time() - (stat("$file"))[9];
  if($logModification <= $logTime){
    addMessage $ok,"Backup file has less than $logTime seconds ($logModification)";
  }else{
    addMessage $warning,"Backup file has more than $logTime seconds ($logModification)";
  }
}


open (my $fh, '<:encoding(UTF-8)', "$file") or usage "backup log $file not found";
while (my $line = <$fh>) {
    if ($line =~ m/^\[OK\] (.*)/) {
        addMessage $ok,$1;
    }elsif ($line =~ m/^\[KO\] (.*)/) {
        addMessage $critical,$1;
    }
  $seemsTbeComplete = 1 if $line =~ m/$lastCheck/;
}

if ($seemsTbeComplete){
  addMessage $ok,"Backup seems to be complete";
}else{
  addMessage $critical,"Backup doen't seems to be complete : '$lastCheck' not found";
}

$exitMessage = "[".$statusName[$status]."] Backup log $file".$messageSeparator.$exitMessage;
finalExit;
