#!/exlibris/aleph/a22_1/product/bin/perl
#
#The script checks items expanded in BIB field as to their proper item status, collection, callNo, barode and material.
#See manual for mor instructions
#created by Matyas Bajger, University of Ostrava  matyas.bajger@osu.cz 2015
#
#  !!! First set your BIB and ADM libaries on the next lines
my $BIBbase='osu01'; 
my $ADMbase='osu50'; 
# By the next scalar you can switch language of warning on checkis; Available values: ENG (Eenglish, default), CZE (Czech)
my $lang='CZE';

use strict;
use warnings;
use utf8;
binmode STDOUT, ":utf8";
binmode STDIN, ":utf8";
binmode STDERR, ":utf8";
use open ":encoding(utf8)";
use POSIX qw/strftime/;
use Data::Dumper;
use DBI;
use Scalar::Util qw(looks_like_number);
use Env;
use Switch;
$ENV{NLS_LANG} = 'AMERICAN_AMERICA.AL32UTF8';


sub run_exemption {
   my $message = $_[0]; my $level = uc($_[1]);
   if ( defined my $mailTo ) {
      open(MAIL, "|/usr/sbin/sendmail -t");
      print MAIL "To: $mailTo\n";
      print MAIL 'From: aleph@library.gen'."\n";
      print MAIL "Subject: osu_item_check_onfly.pl $level\n\n";
      print MAIL localtime()." $level : $message\n"; 
      close(MAIL);
      }
   }

#read settings file
$ADMbase=lc($ADMbase); $BIBbase=lc($BIBbase);
my $libSettinsFile=$ENV{$ADMbase.'_dev'}; $libSettinsFile = $libSettinsFile."/$ADMbase/tab/osu_item_location_check";
unless (open ( FILESET, "<$libSettinsFile" ) ) { run_exemption("File $libSettinsFile cannot be opened for reading in $ADMbase library (/tab directory)",'warning'); }
my $globSettings={};
my @settings=([],[]);
while( <FILESET> ) {  #check tab44 contents
   my $setLine = $_;
   $setLine =~ s/^\s+|\s+$//g; #trim
#read setting file - global settings
   next if ( substr($setLine,0,1) eq '!' );
   if (  substr($setLine,0,1) eq '@' ) { #global settings
      my $globVarName = $setLine; $globVarName =~ s/\s*=.*$//; $globVarName =~ s/^\s*@\s*//; $globVarName=lc($globVarName);
      my $globVarValue = $setLine; $globVarValue =~ s/^.*=\s*//;
      if ( $globVarName and $globVarValue) { $globSettings->{$globVarName} = $globVarValue; }
      next;
      }
#particular settings - collections, statuses, call-nos, materials, barcodes
   while ( length($setLine)<82 ) { $setLine.=' '; }
   my $coll=substr($setLine,0,5); 
   my $status=substr($setLine,6,2);
   my $callNoFrom=substr($setLine,9,17);
   my $callNoTo=substr($setLine,27,17);
   my $material=substr($setLine,45,5);
   my $barcodeFrom=substr($setLine,51,15);
   my $barcodeTo=substr($setLine,67,15); 
   my @settingsLine=($coll,$status,$callNoFrom,$callNoTo,$material,$barcodeFrom,$barcodeTo);
   push (@settings,\@settingsLine);   
   }
my $omitProcessStatuses;
if ( $globSettings->{'omit_process_statuses'} ) {
   $omitProcessStatuses = $globSettings->{'omit_process_statuses'} =~ s/,/)|(/g;
   $omitProcessStatuses =~ s/^\s*/(/; $omitProcessStatuses =~ s/\s*$/)/; }
else { $omitProcessStatuses = ''; }
my $omitProcessStatusesRex = qr/${omitProcessStatuses}/;
my $mailTo = $globSettings->{'mail_results'};
close ( FILESET );
my $bad = '';



#subs/procedures for checking items
sub check_status {
   my ($i,$s) = @_;
   unless ( @$s[1] ) { return check_callNo($i,$s); }
   if ( $i->{'STATUS'} eq @$s[1] ) {
      return check_callNo($i,$s); }
   else {
      return ( $bad !~ /barcode|material|callno/ ? 'status' : $bad ); }
   }

sub check_callNo {
   my ($i,$s) = @_;
   my $is = $i->{'CALLNO'} || ''; 
   $is =~ s/([0-9]+)/sprintf('%020s',$1)/ge; $is=uc($is); $is=~s/^\s+|\s+$//g;
   my $ssf = @$s[2] || ''; $ssf =~ s/([0-9]+)/sprintf('%020s',$1)/ge; $ssf=uc($ssf); $ssf=~s/^\s+|\s+$//g;
   my $sst = @$s[3] || ''; $sst =~ s/([0-9]+)/sprintf('%020s',$1)/ge; $sst=uc($sst); $sst=~s/^\s+|\s+$//g;
   unless ( $ssf and $sst ) { 
      return check_material($i,$s); }
   if ( $ssf and !$sst) { $sst='ZZZZZZZZZZZZZZZ'; }
   unless ( $ssf lt $sst) {  
      run_exemption ("WARNING - mishmash in settings - call No $ssf does not look lesser than $sst. Skipping check of callNos",'warning'); 
      return check_material($i,$s); }
   if ( ( $is ge $ssf ) and ( $is le $sst ) ) {
      return check_material($i,$s); }
   else {
       return ( $bad !~ /barcode|material/ ? 'callno' : $bad ); }
   }
sub check_material {
   my ($i,$s) = @_;
   @$s[4]='' unless (@$s[4]);
   @$s[4] =~ s/^\s+|\s+$//g;
   unless ( @$s[4] ) { 
      return check_barcode($i,$s); }
   if ( $i->{'MATERIAL'} eq @$s[4] ) { 
      return check_barcode($i,$s); }
   else { return ( $bad ne 'barcode' ? 'material' : $bad ); }
   }
sub check_barcode {
   my ($i,$s) = @_;
   my $ib = $i->{'BARCODE'} || ''; $ib=~s/^\s+|\s$//;
   my $sbf = @$s[5] || ''; $sbf=~s/^\s+|\s$//;
   my $sbt = @$s[6] || ''; $sbt=~s/^\s+|\s$//;
   unless ( $sbf and $sbt ) { 
      return ''; }
   if ( $sbf and !$sbt) { $sbt='ZZZZZZZZZZZZZZZ'; }
   unless ( $sbf lt $sbt) {
      run_exemption ("WARNING - mishmash in settings - barcode $sbf does not look lesser than $sbt. Skipping check of barcodes",'warning');
      return ''; }
   if ( ( $ib ge $sbf ) and ( $ib le $sbt ) ) {
      return ''; }
   else { return 'barcode' ;} 
   }

#read+write lines from stdin and perform check of items
while (<>) { 
   my $line=$_;
   $line =~ s/^\s+|\s+$//g;
   last if ( $line eq '' );
   next if ( $line =~ m/^$BIBbase/i );
   if ( $line =~ m/^CHK30/ ) {
      my $item={};
      $item->{'PROCESS_STATUS'} = ( $line =~ /\$\$0(.*)/ ? $1 : '' ); $item->{'PROCESS_STATUS'} =~ s/\$\$.*$//;
      $item->{'COLLECTION'} = ( $line =~ /\$\$1(.*)/ ? $1 : '' ); $item->{'COLLECTION'} =~ s/\$\$.*$//;
      $item->{'STATUS'} = ( $line =~ /\$\$2(.*)/ ? $1 : '' ); $item->{'STATUS'} =~ s/\$\$.*$//;
      $item->{'CALLNO'} = ( $line =~ /\$\$3(.*)/ ? $1 : '' ); $item->{'CALLNO'} =~ s/\$\$.*$//;
      $item->{'MATERIAL'} = ( $line =~ /\$\$4(.*)/ ? $1 : '' ); $item->{'MATERIAL'} =~ s/\$\$.*$//;
      $item->{'BARCODE'} = ( $line =~ /\$\$5(.*)/ ? $1 : '' ); $item->{'BARCODE'} =~ s/\$\$.*$//;
      #omit item process statuses
      next if ( $item->{'PROCESS_STATUS'} =~ /$omitProcessStatuses/ or $omitProcessStatusesi eq '' );
      $bad = '';
      for my $setl (@settings) {
	 #check collection
	 next unless (@$setl[0]);
	 my $sc = @$setl[0]; $sc=~s/^\s+|\s$//;
	 $sc=~s/\*/.*/g;
	 $sc=~s/\?/.*/g;
	 if ( $item->{'COLLECTION'} =~ m/^$sc$/i ) {
	    $bad = check_status($item,$setl);
	    last unless ($bad);
	    }
	 }   
      #create field with warning
      if ( $bad ) { 
         switch ( ($lang || '') ) {
            case 'CZE' {          
               switch ($bad) {
                  case 'status' { $bad='statusu jednotky: '.$item->{'STATUS'}; }
                  case 'callno' { $bad='signatuře'; }
                  case 'material' { $bad='druhu dokumentu: '.$item->{'MATERIAL'}; }
                  case 'barcode' { $bad='čárovém kódu'; }
                  }
               print 'CHK30L$$aJednotka '.( $item->{'BARCODE'} ? 'č.kód '.$item->{'BARCODE'}.' ' : '' ).( $item->{'CALLNO'} ? 'signatura '.$item->{'CALLNO'}.' ' : '' )."má chybu v $bad\n";
               }
            else {
               switch ($bad) {
                  case 'status' { $bad='item status: '.$item->{'STATUS'}; }
                  case 'callno' { $bad='call number'; }
                  case 'material' { $bad='item material: '.$item->{'MATERIAL'}; }
                  case 'barcode' { $bad='barcode: '; }
                  }
               print 'CHK30L$$aItem '.( $item->{'BARCODE'} ? 'barcode '.$item->{'BARCODE'}.' ' : '' ).( $item->{'CALLNO'} ? 'call-no '.$item->{'CALLNO'}.' ' : '' )."has a mistake in $bad.\n";
               }
            }
         }
      }
   else { print "$line\n"; }
   }

