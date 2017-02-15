#!/exlibris/aleph/a22_1/product/bin/perl
#
#The script checks items in ADM libraries as to their proper item status, collection, callNo, barode and material.
#It can be useful to have control over proper specifications of items according to your library division and regules,
#     as no such check exists natively in ALEPH (ver 22)
#
#Allowed combinations of items' properties are to be set in the file $data_tab/osu_item_location_check in the ADM base
#
#All ADM libraries are investigated according to ENV variables $ALEPH_LIBS and $XXX5N_dev
#
#The result is html table with coulour (red) labeling of mistakes found.
#The result file might be sent to a responsible staff to e-mail according to settings in osu_item_location_check tab
#
#This script can be run by hand, yet regular execution using cron or ALEPH's job_list is recommended
#
##Arguments: 
#          1 - output file with full path  (html with table report)
#                 if no argument is adeed the result file is: items_error.html          
#
#The script has no log, running info goes to current STDOUT
#
# !! if you lile to have this fule executable, change the first line
#                      #!/exlibris/aleph/a22_1/product/bin/per
# !!to your real path to perl
#
#
#Examples of running:
#command line:
#  >items_location_check.pl library_mess.html >items_location_check.log
#ALEPH's joblist line (every weekend check (remove the first comment char #]
#00 07:00:00 N items_location_check /{path_to_script}/items_location_check.pl library_mess.html
#
#
#created by Matyas Bajger, University of Ostrava  matyas.bajger@osu.cz 2015
#
use strict;
use warnings;
use utf8;
binmode(STDOUT, ":utf8");
binmode(STDIN, ":utf8");
binmode STDIN, ":encoding(UTF-8)";
binmode STDOUT, ":encoding(UTF-8)";
use POSIX qw/strftime/;
use Data::Dumper;
use DBI;
use locale;
$ENV{NLS_LANG} = 'AMERICAN_AMERICA.AL32UTF8';

my $reportFile = $ARGV[0] || 'items_error.html';
my $debug=0; #set value to 1 (true) for enhanced logging

sub run_exemption {
   my $message = $_[0]; my $level = uc($_[1]);
   print localtime()." ".uc($level)." : $message\n";
   if ( defined my $logFile ) {
     if ( tell(LOGFILE) == -1 ) { open ( LOGFILE, ">>$logFile" ); }
     print LOGFILE localtime()." $level : $message\n"; 
     close (LOGFILE);
     }
   if ( defined my $mailTo ) {
      open(MAIL, "|/usr/sbin/sendmail -t");
      print MAIL "To: $mailTo\n";
      print MAIL 'From: aleph@library.gen'."\n";
      print MAIL "Subject: items_location_check.pl $level\n\n";
      print MAIL localtime()." $level : $message\n"; 
      close(MAIL);
      }
   if ( $level eq 'ERROR' or $level eq 'ERR' ) { print "Exiting...\n"; exit 0;}
   }

#check ALEPH libraries for item definition table. If found in /tab directory, items in the library are checked
my $alephLibsScalar = $ENV{ALEPH_LIBS} or run_exemption('Env variable ALEPH_LIBS not found! I cannot find which libraries should be inspected.','error');
my @alephLibs = split (' ',$alephLibsScalar);
my @libs2check;
while ( my $lib = lc(shift(@alephLibs)) ) {
   my $libTab = $ENV{$lib.'_dev'} or run_exemption("Env variable $lib"."_dev not found. I cannot determine the home directory of the $lib library and check it.",'warning');
   unless ( $libTab ) {
      run_exemption("Env variable $lib"."_dev not found. I cannot determine the home directory of the $lib library and check it.",'warning');
      next; }
   #Tcheck tab dir, check file exist
   unless ( -d $ENV{$lib.'_dev'}."/$lib/tab" ) { 
      run_exemption("Directory ".$ENV{$lib.'_dev'}."/$lib/tab defined by env variable $lib"."_dev not found. Library $lib cannot be checked.",'warning');
      next; }
   if ( -e $ENV{$lib.'_dev'}."/$lib/tab/osu_item_location_check" ) { push(@libs2check,$lib); }
   }

#loop through libraries to be checked
if ( scalar @libs2check == 0 ) { run_exemption ('No ALEPH libraries to check...','error'); }
while ( my $lib = shift(@libs2check) ) {
my $libSettinsFile=$ENV{$lib.'_dev'}."/$lib/tab/osu_item_location_check";
unless (open ( FILESET, "<$libSettinsFile" ) ) { run_exemption("File $libSettinsFile cannot be opened for reading. Skipping check of $lib library",'warning'); next; }
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
#particular settings do hashe settings
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
   $omitProcessStatuses = $globSettings->{'omit_process_statuses'} =~ s/,/','/g;
   $omitProcessStatuses =~ s/^\s*/z30_item_process_status not in \('/;
   $omitProcessStatuses =~ s/\s*$/');/; }
else { $omitProcessStatuses = '(z30_item_process_status is null or ascii(z30_item_process_status)=32)'; }
my $mailTo = $globSettings->{'mail_results'};
my $oracleAddress = $globSettings->{'oracle_address'} ? $globSettings->{'oracle_address'} : 'localhost';
close ( FILESET );
my $bad = '';


#subs/procedures for checking items
sub check_status {
   my ($i,$s) = @_;
   unless ( @$s[1] ) { 
      if ($debug) {print "no check status\n";}
      return check_callNo($i,$s); } 
   if ($debug) {print "checking status ".$i->{'STATUS'}.' eq '.@$s[1]."\n";}
   if ( $i->{'STATUS'} eq @$s[1] ) { 
      if ($debug) {print "status ok\n";}
      return check_callNo($i,$s); }
   else { 
      return ( $bad !~ /barcode|material|callno/ ? 'status' : $bad ); }
   }
sub check_callNo {
   my ($i,$s) = @_;
   my $is = $i->{'CALLNO'} || ''; $is =~ s/([0-9]+)/sprintf('%020s',$1)/ge; $is=uc($is); $is=~s/^\s+|\s+$//g;
   my $ssf = @$s[2] || ''; $ssf =~ s/([0-9]+)/sprintf('%020s',$1)/ge; $ssf=uc($ssf); $ssf=~s/^\s+|\s+$//g;
   my $sst = @$s[3] || ''; $sst =~ s/([0-9]+)/sprintf('%020s',$1)/ge; $sst=uc($sst); $sst=~s/^\s+|\s+$//g;
   unless ( $ssf and $sst ) { 
      if ($debug) {print "no check callNo\n";}
      return check_material($i,$s); }
   if ( $ssf and !$sst) { $sst='ZZZZZZZZZZZZZZZ'; }
   unless ( $ssf lt $sst) {  
      run_exemption ("WARNING - mishmash in settings - call No $ssf does not look lesser than $sst. Skipping check of callNos",'warning'); 
      return check_material($i,$s); }
   if ($debug) {print "checking callNo ( $is lt $ssf ) or ( $is gt $sst ) \n";}
   if ( ( $is ge $ssf ) and ( $is le $sst ) ) {
      if ($debug) {print "callNo ok\n";}
      return check_material($i,$s); }
   else {
       return ( $bad !~ /barcode|material/ ? 'callno' : $bad ); }
   }
sub check_material {
   my ($i,$s) = @_;
   @$s[4] =~ s/^\s+|\s+$//g;
   unless ( @$s[4] ) { 
      if ($debug) {print "no check material\n";}
      return check_barcode($i,$s); }
   if ($debug) {print "checking material ".$i->{'MATERIAL'}.' eq '.@$s[4]."\n";}
   if ( $i->{'MATERIAL'} eq @$s[4] ) { 
      if ($debug) {print "material ok\n";}
      return check_barcode($i,$s); }
   else { return ( $bad ne 'barcode' ? 'material' : $bad ); }
   }
sub check_barcode {
   my ($i,$s) = @_;
   my $ib = $i->{'BARCODE'} || ''; $ib=~s/^\s+|\s+$//g;
   my $sbf = @$s[5] || ''; $sbf=~s/^\s+|\s+$//g;
   my $sbt = @$s[6] || ''; $sbt=~s/^\s+|\s+$//g;
   unless ( $sbf and $sbt ) { 
      if ($debug) {print "no check barcode - ITEM LOOKS OK\n";}
      return ''; }
   if ( $sbf and !$sbt) { $sbt='ZZZZZZZZZZZZZZZ'; }
   unless ( $sbf lt $sbt) {
      run_exemption ("WARNING - mishmash in settings - barcode $sbf does not look lesser than $sbt. Skipping check of barcodes",'warning');
      return ''; }
   if ( ( $ib ge $sbf ) and ( $ib le $sbt ) ) {
      if ($debug) {print "barcode ok - ITEM LOOKS OK\n";}
      return ''; }
   else { return 'barcode' ;} 
   }


#read items from database
unless ( $ENV{'ORACLE_SID'} ) {run_exemption('Env variable ORACLE_SID not found. I cannot connect to Oracle!','error');}
my $sid = 'dbi:Oracle:host='.$oracleAddress.';sid='.$ENV{'ORACLE_SID'};
unless ( $ENV{'aleph_exe'} ) { run_exemption('Env variable "aleph_exe" not found. I cannot find the aleph/exe directory!','error');}
my $libPas;
my @report=([],[]);
if ( -e $ENV{'aleph_exe'}.'/get_ora_passwd' ) { $libPas=`$ENV{'aleph_exe'}'/get_ora_passwd' $lib`; }
else { $libPas=$lib;}
unless ( defined $libPas ) {$libPas=$lib;}
my $dbh = DBI->connect($sid, $lib,$libPas) or run_exemption ("ERROR couldn't connect to database sid $sid, user  $lib / $libPas :: ".$DBI::errstr,'error');
my $sth0 = $dbh->prepare("select z30_rec_key reckey, trim(z30_collection) collection, z30_item_status status, trim(z30_call_no) callno, z30_material material, trim(z30_barcode) barcode from z30 where $omitProcessStatuses");
$sth0->execute or run_exemption ("ERROR in sql ".$DBI::errstr."\n I cannot get items from the database!",'error');
while(  (my $item = $sth0->fetchrow_hashref())  ) {
   print "checking item ".$item->{'RECKEY'}."\n";
   $bad = '';

   for my $setl (@settings) {
      next unless (@$setl[0]);
      my $sc = @$setl[0]; $sc=~s/^\s+|\s+$//g;
      $sc=~s/\*/.*/g;
      $sc=~s/\?/.*/g;
      if ($debug) {print 'checking $item->{\'COLLECTION\'} =~ m/^$sc$/i : '.$item->{'COLLECTION'}.' =~ m/^'.$sc.'$/i '."\n";}
      if ( $item->{'COLLECTION'} =~ m/^$sc$/i ) {
         if ($debug) {print "match\n";}
         $bad = check_status($item,$setl);
         last unless ($bad);
         }
      }   

   if ( $bad ) { 
      print $item->{'RECKEY'}." looks bad: $bad\n";
      my @bi=($bad,$item->{'RECKEY'},$item->{'COLLECTION'},$item->{'STATUS'},$item->{'CALLNO'},$item->{'MATERIAL'},$item->{'BARCODE'});
      push (@report,\@bi);
      }
   }


open (REPORT,">$reportFile") or run_exemption ("ERROR - report file $reportFile cannot be opened. I cannot create report with results. Exiting.",'error');
print REPORT '<html><head><meta http-equiv="content-type" content="text/html; charset=utf-8"></head><body>'."\n";
print REPORT "<h1>Items check report</h1>\n";
my $datestring = strftime "%e.%m.%Y %H:%M:%S", localtime;
print REPORT "<p><em>$datestring</em></p>\n";
if ( scalar @report == 0 ) { print REPORT "<p>Everything's O.K.</p>\n";}
else { 
   print REPORT '<table border="1">'."\n"; 
   print REPORT '<tr><th>Item key</th><th>Collection</th><th>Item status</th><th>Call No.</th><th>Material</th><th>Barcode</th>'."\n"; 
   for my $line ( @report ) {
      next if ((@$line[1] || '') eq '');
      print REPORT "   <tr>\n";
      print REPORT '      <td style="color:black;">'.(@$line[1] || '')."</td>\n";
      print REPORT '      <td style="color:'.((@$line[0]||'') eq 'collection' ? 'red' : 'black').';">'.(@$line[2]||'[missing]')."</td>\n";
      print REPORT '      <td style="color:'.((@$line[0]||'') eq 'status' ? 'red' : 'black').';">'.(@$line[3]||'[missing]')."</td>\n";
      print REPORT '      <td style="color:'.((@$line[0]||'') eq 'callno' ? 'red' : 'black').';">'.(@$line[4]||'[missing]')."</td>\n";
      print REPORT '      <td style="color:'.((@$line[0]||'') eq 'material' ? 'red' : 'black').';">'.(@$line[5]||'[missing]')."</td>\n";
      print REPORT '      <td style="color:'.((@$line[0]||'') eq 'barcode' ? 'red' : 'black').';">'.(@$line[6]||'[missing]')."</td>\n";
      print REPORT "   </tr>\n";
      }
   print REPORT "</table>\n"; 
   }
print REPORT '</body></html>';
close (REPORT);

if ( defined $mailTo ) {
   print "sending report to $mailTo\n";
   open my $rep, '<', $reportFile or run_exemption ("ERROR - output report file $reportFile not found (when I wanted to sent id to you by e-mail).",'warning');
   my $rtext = do {  local $/;  <$rep> };
   close $rep;
   open(MAIL, "|/usr/sbin/sendmail -t");
   print MAIL "To: $mailTo\n";
   print MAIL 'From: aleph@library.gen'."\n";
   print MAIL "Subject: Items location check\n";
   print MAIL "Content-type: text/html\n\n";
   print MAIL "$rtext\n\n";
   close(MAIL);
   }
}
