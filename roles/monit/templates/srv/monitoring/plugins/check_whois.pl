#!/usr/bin/perl
#{{ ansible_managed }}

#===============================================================================
# Auteur : pihomecloud
# Date   : 11/11/2015
# But    : Vérification de l'expiration d'un nom de domaine
#===============================================================================


use strict;
use warnings;
use Date::Parse;
use Getopt::Long;

my $domain;
my $verbose;
my $warningDays = 60;
my $criticalDays = 15;


my ($ok, $warning, $critical, $unknown, $dependant) = (0,1,2,3,4);
my @statusName = ('OK', 'WARNING', 'CRITICAL', 'UNKNOWN', 'DEPENDANT');

my $status = $ok;
my $exitMessage = "";
my $messageSeparator = ",\n";
my $errorOnly;
my $host="whois.gandi.net";
my $regexp="(Registrar Registration Expiration|Registry Expiry) Date";


sub usage {
  my $message = shift;
  print $message."\n" if $message;
  print "Usage : $0 [-d |--domain=]domain [-v|--verbose] [-r |regexp=]regexp [-h |--host=]host\n";
  print "      domain : domain name to check\n";
  print "      host : whois server to use (default : whois.gandi.net)\n";
  print "      regexp : regexp for fin expiration date (default : Registry Expiry Date:)\n";
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
  status $tStatus if $tStatus;
  $exitMessage = "[".$statusName[$status]."] Check is ".$statusName[$status]." " unless $exitMessage;
  $exitMessage.=$message if $message;
  print $exitMessage."\n";
  exit $status;
}

sub addMessage {
  my $tStatus = shift;
  my $message = join(' ', @_);
  status $tStatus;
  if ($tStatus > $ok or !$errorOnly){
    $exitMessage .= $messageSeparator if $exitMessage;
    $exitMessage .= "[".$statusName[$tStatus]."] ".$message;
  }
}


GetOptions( 'domain|d=s' => \$domain, 'verbose|v' => \$verbose, 'h|host=s' =>\$host,
            'warning|w=i' => \$warningDays, 'critical|c=i' => \$criticalDays
          ) or usage "Invalid parameter";

usage "domain is mandatory" unless $domain;
usage "warning ($warningDays) must be greater or equal critical ($criticalDays)" if $warningDays < $criticalDays;


my $cmd="whois -h $host $domain";
print "Verb : 'warning|w=i' => $warningDays, 'critical|c=i' => $criticalDays\n" if $verbose;
print "Verb : cmd \n" if $verbose;
my @whoisOutput=`$cmd 2>&1`;
my $additionnalInfos;

print "Verb : whoisOutput \n".join("",@whoisOutput)."\n-----------------------------\n" if $verbose;

foreach (@whoisOutput){
  chomp;
  #print "Verb : ".$_."\n" if $verbose;
  $additionnalInfos .= $_ if /^Domain Name/;
  $additionnalInfos .= $messageSeparator.$_ if /Registrar:/;
  if (/$regexp/){
    my $now = time();
    my $expireStr = $_;
    $expireStr =~ s/.*\s//;
    print "Verb : Now : $now \n" if $verbose;
    print "Verb : expire : $expireStr \n" if $verbose;
    my $timeRemaining = str2time($expireStr) - $now;
    print "Verb ; remaining sec : $timeRemaining\n" if $verbose;
    $timeRemaining = int($timeRemaining/86400);
    print "Verb ; remaining days : $timeRemaining\n" if $verbose;
    if ($timeRemaining <= $criticalDays){
      addMessage $critical,"$timeRemaining days before expiration (<= $criticalDays)";
    }elsif ($timeRemaining <= $warningDays){
      addMessage $warning,"$timeRemaining days before expiration (<= $warningDays)";
    }else{
      addMessage $ok,"$timeRemaining days before expiration (> $warningDays)";
    }
  }
}

print "Verb : exitMessage : $exitMessage\n" if $verbose and not $exitMessage;
addMessage $unknown,"No date found : \n".join($messageSeparator,@whoisOutput) unless $exitMessage;
$exitMessage .= $messageSeparator.$additionnalInfos if $additionnalInfos;
finalExit;
