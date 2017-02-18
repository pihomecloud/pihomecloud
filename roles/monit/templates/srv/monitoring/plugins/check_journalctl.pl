#!/usr/bin/env perl
#{{ ansible_managed }}

#===============================================================================
# Auteur : pihomecloud
# Date   : 11/11/2015
# But    : Vérification du journal via journaltcl
#===============================================================================
use strict;
use warnings;
use Getopt::Long;
use Data::Dumper;
use JSON;
use Time::Piece;

my $VERSION = '1.0';

my ($ok, $warning, $critical, $unknown, $dependant) = (0,1,2,3,4);
my @statusName = ('OK', 'WARNING', 'CRITICAL', 'UNKNOWN', 'DEPENDANT');

my $status = $ok;
my $exitMessage = "";
my $messageSeparator = ",<br/>\n";
my $errorOnly;
my $verbose;

sub usage {
  my $message = shift;
  print $message."\n" if $message;
  print "Usage : $0 [-m |--minutes=]minutes [-e|--erroronly]\n";
  print "  minutes : nombre de minutes a surveiller\n";
  print "  erroronly : uniquement les messages de type 'err'\n";
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
  print "Verb : Adding [".$statusName[$tStatus]."] ".$message."\n" if $verbose;
  status $tStatus;
  $exitMessage .= $messageSeparator if $exitMessage;
  $exitMessage .= "[".$statusName[$tStatus]."] ".$message;
}


my $minutes=30;
my $priority='warning';
GetOptions( 'minutes|m=i' => \$minutes, 'verbose|v' => \$verbose, 'error|e' => \$errorOnly) or usage;


if($errorOnly){
  $priority='err';
}

my $cmd="sudo -S journalctl -p $priority --no-full --no-pager -o json  ";

#Cas du boot avec horloge désynchronisée...
my $bootTime=`sed -n '/^btime /s///p' /proc/stat`;
chomp $bootTime;
my $now = time;

my $timediff = ($now-$bootTime)/60;

print "Verb : boot time : $bootTime\n" if $verbose;
print "Verb : now  time : $now\n" if $verbose;
print "Verb : minutes from boot : $timediff\n" if $verbose;

if($timediff < $minutes){
  #Whohoho il faudrait changer la pile du BIOS quand même
  #J'enleve quelques secodes pour eviter les duplications de lignes (chez moi le kernel met 5 secondes a démarrer, et vous ? :p)
  my $bootTimeFormat=localtime($bootTime-5)->strftime('%F %T');
  $cmd .= " --since=-${minutes}m --until='$bootTimeFormat' </dev/null;$cmd -b </dev/null";
}else{
  #On va pas se taper toutes les logs, mais que'est ce que c'est que cette commande --since ?? fabuleux non ?
  $cmd .= " --since=-${minutes}m";
 
  #On supprime l'entrée standard, au cas ou on a un mot de passe amettre ;p
  $cmd .= " </dev/null";
}

print "Verb : Executing '$cmd'\n" if $verbose;
my @journal=`$cmd`;
print "Verb : ".($#journal+1)." entries found\n" if $verbose;
if($? >0 or $#journal == 0){
  #y'a pas de doc, j'ai la flemme, y'a qu'a essayer si ca marche après tout...
  addMessage $unknown,"Whoops, $cmd returned $?";
#J'utilise un regexp car je ne sais pas ce qu'il peut y avoir à la fin \n ou rien
}elsif($journal[0] !~ /-- No entries --/){
  foreach my $json (@journal){
    my $lStatus = $warning;
    chomp $json;
    print "Verb : Journal entry : $json\n" if $verbose;
    my $entry = JSON->new->utf8->decode($json);
    print Dumper($entry) if $verbose;
    if(defined $$entry{PRIORITY} and $$entry{PRIORITY} <= 3){
      $lStatus=$critical;
    }
    my $timeStamp =($$entry{__REALTIME_TIMESTAMP}/1000000);
    my $date = localtime($timeStamp);
    my $hostname = $$entry{_HOSTNAME};
    my $messageToAdd=localtime($timeStamp)." ".$$entry{_HOSTNAME}." ".$$entry{_TRANSPORT};
    $messageToAdd .= " ".$$entry{_COMM} if $$entry{_COMM};
    $messageToAdd .= "[".$$entry{_PID}."]" if $$entry{_PID};
    $messageToAdd .= " ".$$entry{MESSAGE} if $$entry{MESSAGE};
    $messageToAdd .= " COMMAND=".$$entry{_CMDLINE} if $$entry{_CMDLINE};
   
    addMessage $lStatus, $messageToAdd;
  }
}else{
  addMessage $ok,"No error found sine $minutes minutes";
}

finalExit;
