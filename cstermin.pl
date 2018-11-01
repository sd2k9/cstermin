#!/usr/bin/perl
# file name: ''cstermin.pl''
#  project: cstermin
# function: Small scheduler in the style of how Cross Secretary
#           for XP once worked
#
#      created: 27.04.2k4
#  last change: See git history
#      Version: See git tag
# Copyright (C) 2004,2006,2018 Robert Lange <sd2k9@sethdepot.org>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# version 3 as published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.


# ******************** MODIFY CUSTOM SETTING BELOW THIS LINE *******************
# *** Prefix for Today and Passed Appointments ***
# the following prefis is printed in front of a passed appointment
my $prefix_app_passed = "PASSED";
# the following prefis is printed instead of the date of an appointment today
my $prefix_app_today = "TODAY";

# *** Highlighting for Today and Passed Appointments ***
# the following attributes are passed in a Pango <span> markup tag
# to highlight "PASSED" and "TODAY" (the words)
# see the Pango documentation, section Text Attribute Markup
# *** Highlighting for TODAY
# No Highlighting
# my $markup_app_passed = '';
# Magenta Text Color
# my $markup_app_passed = 'foreground="magenta"';
# Red Text Color, Bold Face
my $markup_app_passed = 'foreground="red" weight="bold"';
# *** Highlighting for PASSED
# No Highlighting
# my $markup_app_today = '';
# Brown Text Color
# my $markup_app_today = 'foreground="brown"';
# Blue Text Color, Oblique Style
my $markup_app_today = 'foreground="blue" style="oblique"';

# *** date format settings ***
# uncomment (e.g. remove the leading #) for one line of each set
# output date order (does not modify the given order in the config file)
# german dd.mm.yyyy
my $date_format_sub = sub{my $x = shift; return "$$x{'day'}.$$x{'month'}.$$x{'year'}" };
# american mm.dd.yyyy
# my $date_format_sub = sub{my $x = shift; return "$$x{'month'}.$$x{'day'}.$$x{'year'}" };
# ISO yyyy-mm-dd
# my $date_format_sub = sub{my $x = shift; return "$$x{'year'}-$$x{'month'}-$$x{'day'}" };

# **************************** END OF CUSTOM SETTINGS **************************
# *** DON'T CHANGE ANYTHING BELOW THIS LINE UNTIL YOU KNOW WHAT YOU'RE DOING ***


# *** packes to use ***
use strict 'refs';
use warnings;
use Getopt::Long;
use FindBin;

# CPAN packages
use Time::ParseDate;  # Time-modules

# Gtk2-Package is included after variable declaration


# *** furter settings needed by the program ***
my $Prog_Name = "cstermin.pl";
# Marker for Options in the config file
my $Options_Prefix = "Options: ";
# this also works as a docu of the available options
# Name of the known options
my %Options_Names = (
   # Abbreviations: A - will be set automatically by this program
   #                B - binary Yes/No Option
   #                    0, No, False, not in config file: not set
   #                     everything else: set
   # Always Option Value case-insensitive, Option name case-sensitive
   # Name of the Option for saving the last running date of the script
   Last_Run => "Last-Run",    # format: dd.mm.yyyy         A
   # Output the appointments to the console window
   'Output-Console' => 'Output-Console',  #  format: B
   # Output the appointments with the help of a Gtk2 Widget
   'Output-Gtk2' => 'Output-Gtk2',     #  format: B
   # run in any case, even if we were called already this day
   'Force-Run' => 'Force-Run', #  format: B
   # allow modification of the config file
   Modify => 'Modify',       #  format: B
   # print Debug Messages
   Debug => 'Debug'       #  format: B
);
# this expression detects a 'false' value given for binary options
my $Options_False_Regexp = qr/^\s*(0|false|no)\s*$/;
# File name of the program icon
my $Icon_File = "$FindBin::RealBin/cstermin.png";

# *** subroutine declarations ***
# main routine without any arguments
sub main ();
# process the loaded schedule file from the global @termine
sub process_termine();
# print the content of the handed over hash
sub format_set(\%\%);
# write back the modified config file
sub write_back();
# load the data from the config file
sub load_config();
# analyse the configfile options and set the options-hash accordingly
sub set_configfile_options();
# *** analyze the command line options
sub set_commandline_options();
# reads the command line options
sub read_commandline();
# does some error checking before exiting; use instead of pure exit
sub exit_cstermin($);
# write the to-print entries to the console window
sub output_console();
# Return version string from CVS tag with copyright
sub versionstring ();
# displays the to-print entries with a Gtk2-Widget
sub output_gtk2();
# format appointments and put into vbox for Gtk2-Widget as markup text label
# 1.P: vbox object
# 2.P: Array reference to Appointments
sub output_gtk2_appointments($\@);
# escape markup characters before applying pango markup in gtk2 label
# 1.P: Reference to Text which should be escaped
sub markup_escape(\$);
# displays the collected error messages in this run
sub error_gtk2();
# Attach cstermin icon to the handed over gtk2 window
# 1.P: window object
sub attach_gtk2_icon ($);
# print error messages to STDERR and stores them for later Gtk2 Display
sub print_error($);

# *** global variables ***
my @termine;          # the data set entries
my $exit_code = 0;     # exit code (initially everything okay)
my $config_mod;        # the modification time of the config file plus one day
                       # undef if not set in config file
my $now = time;        # current time
# the appointments to print, line by line
my @output_content_passed;   # Passed
my @output_content_today;    # Today
my @output_content;          # All Others
# Dealing with Program Options
my %configfile_options;   # Options from config file; write them back later
my %commandline_options;  # Options from the command line
   # sub read_commandline sets the following values to 1 (enabled)
   # or 0 (disabled) when found:
   # Force-Run, Modify, gtk2, Debug
my %options = (        # processed options for use in the program
                       # derived from defaults, Config-File and then command line
   # so we put only values here which can be overwritten and are not modified
   # Binary values share the name with their %Option_Names equivalent
   # Values:
   # Output-Gtk2: true if enabled
   # Output-Console: true if enabled
	       'Output-Console' => 1,
   # Force-Run: true if we run independent of the Last-Run configfile item
   # Modify: true if we are allowed to modify the config file
	       Modify => 1,
   # Debug: true if debug is enabled
   # ConfigFile: default configfile
#	       ConfigFile => "termin.txt"                # for local testing
	       ConfigFile => "$ENV{'HOME'}/.csterminrc"  # for usage
);
my $gtk2_available;      # true when the Gtk2-Package was loaded sucessfully

my $error_messages; # stores error messages, to show them before exit
                    # by Gtk2 if possible

# *** global constants ***
my %exit_codes_meaning = (configerror => 100,
			  commandline => 2
			 );

# ***************************** Documentation ***************************


my $Help_Documentation=<<EOF;

DESCRIPTION

cstermin is a small scheduler for keeping track of recurring
events, like birthdays or one-time appointments.
The appointments are read from an configuration file created
by the user and displayed on the console or with the help of
a Gtk2 widget.

You can configure how long in advance you want to be informed,
if the entry should be deleted after passing, if you want to
be messaged every startup or only once a day and other things.

For more information see the user guide of cstermin.


USAGE

     $Prog_Name [options]

     General Options:
       --help,-h,-?                  This help screen
       --version,-V                  Program version
       --config <file>, -c <file>    Use <file> as configuration file
                                     Default Name is \$HOME/.csterminrc

     Binary Options:
       --output-console, --console   Print appointments in console window
       --output-gtk2, --gtk2         Show appointments in graphical window
       --force-run, --force, --run   Print appointments every run, not
                                     only the first call a day
       --modify, -m                  Allow modification of configuration file
       --debug, -d                   Print debug messages

If a binary option is issued, then it means "set". The long form of this
options can be negated by prepending "no" or "no-", then the option
means "unset".
For example "--debug" means enable debug, but "--no-debug" means
disable debug.

EOF



# *** "body" of the program ***
main();


# *** main routine ***
sub main() {

  # *** Do some Setup
  # Switch Console Output to UTF-8
  binmode(STDOUT, ":utf8");


  # *** Checking for Gtk2-Package
  if (eval "use Gtk2; 1") {
    $gtk2_available = 1;     # Gtk2 is principially available
    # 'declare' constants
    use constant TRUE  => 1;
    use constant FALSE => 0;
  }

  # *** read the command line
  read_commandline();

  # *** load data
  load_config();

  # *** analyze the configfile options
  set_configfile_options();

  # *** analyze the command line options
  set_commandline_options();

  # *** check if we have to run with the help of Last-Run Option
  # okay, we have to do the real test
  if ( defined($configfile_options{$Options_Names{'Last_Run'}}) ) {   # Last_Run option was read
    if ($configfile_options{$Options_Names{'Last_Run'}} =~  /(\d\d)\.(\d\d)\.(\d\d\d\d)\.*/) {
      # format: dd.mm.yyyy
      # correct
      $configfile_options{$Options_Names{'Last_Run'} } = sprintf "%02u.%02u.%04u", $1, $2, $3;
      $config_mod = parsedate("$3/$2/$1 00:00:00");
      # increment to the next day
      $config_mod = parsedate("+1 days", NOW=>$config_mod);
    } else {
      # wrong format; set default again
      print_error "Error in Option $Options_Names{'Last_Run'} of the config file: ";
      print_error "$configfile_options{$Options_Names{'Last_Run'}}\n";
      undef $configfile_options{$Options_Names{'Last_Run'}};
      undef $config_mod;
    }
  } else {                           # Last_Run option unset
    undef $config_mod;
  }

  # now decide upon it whether to run or not
  if ( ! $options{'Force-Run'} ) {
    if ( defined($config_mod) and $config_mod >= $now) {
      print "DEBUG: already run today: aborting\n" if $options{'Debug'};
      exit_cstermin $exit_code;   # we ran already today
    }
  } else { #    if (! defined($_) or ($_ !=~ /$\s*0|false|no\s*^/ ) ) {
    print "DEBUG: forcing run\n" if $options{'Debug'};
  }        #  if ( ! $options{'Force-Run'} )


  # *** decide with output to use
  # only if we have the Gtk2-package, check for the output
  if ( $options{'Output-Gtk2'} and ! $gtk2_available) {
    # Gtk2 requested but bindings failed to load
    print_error "Configuration File requests Gtk2-Output, but " .
      "Module Gtk2 failed to load!\n";
    print_error "     Maybe not installed properly? Falling back to console.\n";
    undef $options{'Output-Gtk2'};  # not
    $options{'Output-Console'} = 1;  # not
  } else {
    print "DEBUG: Gtk2-Output enabled\n" if $options{'Debug'};
  }
  # *** check if we have at least one output enabled
  if (! ($options{'Output-Gtk2'} or $options{'Output-Console'}) ) {
    print "WARNING: No output method selected\n";
  }


  # *** parse them
  process_termine();

  # *** output Termins
  output_console() if $options{'Output-Console'};
  # if we use Gtk2, then create finally the form
  output_gtk2() if $options{'Output-Gtk2'};

  # *** write back
  write_back() if $options{'Modify'};

  # exit without errror
  exit_cstermin $exit_code;
}


# *** load the data from the config file ***
sub load_config() {

  # *** local variable
  my $optname;       # option name

  # *** open, read entries
  open FH, "<:utf8", $options{'ConfigFile'}
    or die "could not open configuraton file \"$options{'ConfigFile'}\": $!\n";
  foreach (<FH>) {
    # decide already upon options or appointments
    if ( $_ =~ /^$Options_Prefix(\S+).*$/ ) {
      $optname = $1;
      # option
      $_ =~ /^$Options_Prefix(\S+) (.*)$/;
      if (defined($2) ) {
	$configfile_options{$optname} = $2;
      } else {
	# fake empty parameter
	$configfile_options{$optname} = "";
      }
    } else {
      # we assume termin
      push @termine, {line => $_};   # anonymous hash reference
    }
  }
  close FH;
}


# analyse the configfile options and set the options-hash accordingly
sub set_configfile_options() {

  # *** settings
  my @which_opts = qw/Force-Run Modify Debug Output-Console Output-Gtk2/;
                     # parse this settings

  # local vars
  my $val;

  foreach (@which_opts) {
    if (defined($configfile_options{$Options_Names{$_}})) {
      $val = lc $configfile_options{$Options_Names{$_}};  # shortcut
      if ($val =~ $Options_False_Regexp ) {
	undef $options{$_};
      } else {
	$options{$_} = 1;
      }
    }
  }
}

# reads the command line options
sub read_commandline() {

  # *** local variables
  my $help;       # set to one if help screen is requested
  my $ver;        # set to one if version is requested

  Getopt::Long::Configure ("bundling");   # enable bundling level 1
  my $result = GetOptions(\%commandline_options,
			  'help|h|?' => \$help,
			  'version|V' => \$ver,
			  'Force-Run|run|force!',
			  'Output-Console|console!',
			  'Output-Gtk2|gtk2!',
			  'Modify|m!',
			  'Debug|d!',
			  'config|c=s' => \$options{'ConfigFile'}
			 );


  if (! $result) {
    print_error "\nFailed to parse the command line options: Exiting\n";
    exit_cstermin $exit_codes_meaning{'commandline'};
  }

  if ( $ver) {
    print "\n$Prog_Name, version " . versionstring()  . "\n";
    exit_cstermin $exit_code;
  }

  if ( $help) {
    print "\n$Prog_Name, version " . versionstring()  . "\n\n";
    print $Help_Documentation;
    exit_cstermin $exit_code;
  }


  # No arguments required: Error when there are some
  if ( @ARGV ) {
    print_error "\nNo arguments expected on command line: Exiting\n";
    exit_cstermin $exit_codes_meaning{'commandline'};
  }


# ZUM AUSGEBEN DES OPTs
#  use Data::Dumper;
# Das verwenden: my %commandline_options;  # Options from the command line
#  print Dumper(%commandline_options);

}


# *** analyze the command line options
sub set_commandline_options() {

  # binary options are easy
  foreach (keys %commandline_options) {
    # override the %options hash if set
    if ($commandline_options{$_} == 0) {
      # undef
      undef $options{$_};
    } else {
      # just copy
      $options{$_} = $commandline_options{$_};
    }
  }
}



# *** process the loaded schedule file ***
# from the global @termine
sub process_termine() {

  # *** local variables
  my $line;         # get the line
  my  %set;         # parsed data for one entry
  my %output_flags; # some flags of the parsed data for printing (one entry)
  my ($href1, $href2); # for turning %set and %output_flags into hash refs
  my $output_entry; # true if we have to print this data
  my ($then, $when);    # time storages <g>
  my %app;          # parsed appointments, key is time since epoch (for sorting)
                    # entry is array (when there are more than one
                    # appointment this date) of arrays
                      # entry 0 is %set, entry 1 is %output_flags

  # *** Parsing Loop: Parse all entries
  foreach (@termine) {

    # Re-Initialise all Variables
    undef %set;
    undef %output_flags;
    undef $output_entry;

    # *** parse it
    $line = $_->{'line'};

    next while $line =~ /^\s*#/; # filter out comments
    next while $line =~ /^\s*$/; # and empty lines
    # format:dd.mm.yy/*|what|flag|time
    if ($line !~ 
        m!^\s*(\d\d)\.(\d\d).(\d\d\d\d|\*{1,4})\|\s*(.*)\s*\|([JYN])\|(\d{1,2})\s*$!) {
      # Match failed
      print_error "Error in the following line from the config file:\n";
      print_error "$line\n";
      $exit_code = $exit_codes_meaning{'configerror'};
      next;
    }
    # Personal DEBUG: print out at first:
    #    print "$line";
    #    print "STARTMATCH\n";
    #    print "$1\n$2\n$3\n$4\n$5\n$6\n";
    #    print "ENDMATCH\n";
    # save in set
    $set{'day'} = $1;
    $set{'month'} = $2;
    $set{'text'} = $4;
    if ($5 eq "J") {
      # correct mode "Ja" to "Yes"
      $set{'mod'} = "Y";        # mode
    } else {
      $set{'mod'} = $5;        # mode
    }
    $set{'adv'} = $6;        # time advance
    # year need special handling
    if ( $3 =~ /\*/ ) {
      # for always entries adjust the date
      $set{'year'} = 1900 + (localtime($now))[5];
      # check if we maybe already passed this date, then increment the year
      # we assume that a difference of 150 days means increment
      if ( $now >
	   (parsedate("$set{'year'}/$set{'month'}/$set{'day'}") + 150*24*60*60) ) {
	++$set{'year'};
      }
    } else {
      $set{'year'} = $3;
    }

    # *** now check, if we have to print out this entry
    $when = parsedate("$set{'year'}/$set{'month'}/$set{'day'} 23:59:59");
    ++$set{'adv'};       # add one day to get the span
    $then = parsedate("-$set{'adv'} days", NOW=>$when);

    if ( $then < $now and $now < $when) {   # normal display
      # generate flags
      $output_flags{'today'} = 1      # it is today
	if (parsedate("-1 days", NOW=>$when) < $now and $now <= $when );
      $output_entry = 1;  # we will print it
    }

    # already passed by
    if ( defined($config_mod) and $config_mod < $when and $when < $now) {
      $output_flags{'passed'} = 1;      # passed by already
      $output_entry = 1;  # we will print it
    }

    # check for deletion of current entry
    $_->{'remove'}=1 if ($when < $now and $set{'mod'} eq "Y");

    # put it into parsed hash, when it should be printed
    if ($output_entry) {
      # Debug
      # use Data::Dumper;
      # print "NEW ENTRY\n" . Dumper( %set, %output_flags);
      push @{$app{$when}}, [{%set}, {%output_flags}]; # anonymous to copy content
    }
  } # End Parsing Loop

  # *** Formatting Loop: Format entries and sort by date
  foreach my $epoch (sort keys %app) {
    # Iterate over every date, because it could contain multiple data
    foreach (@{$app{$epoch}}) {
      format_set(%{$_->[0]}, %{$_->[1]});    # just hand over
    }
  }

  # Output is done after parsing all entries
}



# *** print the content of the handed over hash ***
# 1.P: Reference to one data set
# 2.P: Various Flags which are defined, if true
#      today: appointment is today
#      passed: appointment is already over, but we did not run the exact day
sub format_set(\%\%) {

  # structure of the hash storing one parsed line(e.g. for sub format_set)
  # day:   appointment day
  # month: appointment month
  # year:  appointment year (substituted for annual events)
  # text:  appointment text
  # mod:   modificator of the appointment line in the config file
  # adv: time advance

  my %set = %{$_[0]};     # get parameter (just copy for handyness :-)
  my %flags = %{$_[1]};      # get the associated flags

  # *** do replacement(s) in text
  # multiple replacements of same type are not supported
  my $what = $set{'text'};
  if ($what=~ /\[(\d\d\d\d)\]/) {     # found date replacement
    my $newyear =  $set{'year'} - $1;  # calc difference
    # do subst
    $what=~ s/(\[\d\d\d\d\])/$newyear/;
  }

  # *** do different 'highlightings' while modifying also the appointment time
  #     and put into the correct array
  # highlight today's appointments
  if ($flags{'today'}) {
    push @output_content_today, $prefix_app_today . ": $what";
  } elsif ($flags{'passed'}) {
    push @output_content_passed,
      "$prefix_app_passed " . &$date_format_sub(\%set) . ": $what";
  } else {
    push @output_content, &$date_format_sub(\%set) . ": $what";
  }
}




# write back the (maybe modified) config file
sub write_back() {
  # structure of the termin array:
  # line: the line read from the config file
  # remove: defined if this line is to be removed upon write-back

  # local variables

  print "DEBUG: writing back config file ...\n" if $options{'Debug'};
  # *** modify the last run option
  @_ = localtime($now);
  ++$_[4];         # correct month
  $_[5] += 1900;   # correct year
  $configfile_options{$Options_Names{'Last_Run'}} = sprintf "%02u.%02u.%04u", $_[3], $_[4], $_[5];

  # *** write the stuff
  open FH, ">:utf8", $options{'ConfigFile'}
    or die "could not modify configuraton file \"$options{'ConfigFile'}\": $!\n";
  # first the options
  foreach (sort keys %configfile_options) {
    print FH "$Options_Prefix$_ $configfile_options{$_}\n";
  }
  # now the data
  print "DEBUG: Removing lines from config file:\n" if $options{'Debug'};
  foreach (@termine) {
    if (! defined($_->{'remove'}) ) {    # put back this line
      print FH $_->{'line'};
    }
    else {  print "   $_->{'line'}"  if $options{'Debug'}; }
  }
  close FH;

}


# write the to-print entries to the console window
sub output_console() {

  # Output
  foreach (@output_content_passed, @output_content_today, @output_content) {
    print "$_\n";
  }

}

# return version string from CVS tag with copyright
sub versionstring () {

    my $ver = ' $Name:  $ ';
    $ver =~ s/Name//g;
    $ver =~ s/[:\$]//g;
    $ver =~ s/\s+//g;
    $ver =~ s/^v//g;
    $ver =~ s/_/\./g;
    $ver =~ s/^rev//;
    $ver =~ s/^\.//;
    if ($ver eq '') {
	$ver = "devel";
    }

    $ver . "\n"
      . 'Copyright (C) 2004,2006,2018 Robert Lange <sd2k9@sethdepot.org>' . "\n"
      . 'This program is free software; you can redistribute it and/or' . "\n"
      . 'modify it under the terms of the GNU General Public License'   . "\n"
      . 'version 3 as published by the Free Software Foundation.';
}

# print error messages to STDERR and stores them for later Gtk2 Display
# 1.P: error message to print
sub print_error($) {
  my $error = $_[0];

  # print
  print STDERR $error;

  # and store
  $error_messages = $error_messages . $error;
}


# does some error checking before exiting; use instead of pure exit
# 1.P: exit code to use
sub exit_cstermin($) {

  my $exit_code = $_[0];   # store exit code

  # check if we have/can output error messages with Gtk2
  error_gtk2() if $gtk2_available;

  # and now go away
  exit $exit_code;
}


# ******************************** Gtk2 ******************************

# *** Declaration of Callbacks
sub gtk2_response;

# displays the to-print entries with a Gtk2-Widget
sub output_gtk2() {

  # *** Variables
  my @apps;     # Appointments as local copy, for highlighting

  #  print "DEBUG: Content to display with Gtk2:\n$output_content\n" if $options{'Debug'};

  # do we have something to display?
  if ( @output_content_passed + @output_content_today + @output_content == 0 ) {
    # Nope ...
    return;
  }

  # Init Gkt2
  Gtk2->init;

  # *** Build Widget
  # Next evolution step: Gtk2::Dialog
  # Without Separator line, because I will add this by myself
  my $dialog = Gtk2::Dialog->new('Appointment Days',
				 undef,
				 ['destroy-with-parent', 'no-separator'],
				 '_Later' => 100,         # Later Button
				 'gtk-ok' => 'none'      # OK Button
				);
  $dialog->set_default_response('none');                    # OK is default

  # Try to load Window's icon
  attach_gtk2_icon($dialog);

  # Passed's Appointments: Highlight "Passed"
  @apps = @output_content_passed;
  foreach (@apps) {
    # first escape markup characters
    markup_escape($_);
    # just replace text by hightlighted version
    s|^$prefix_app_passed|<span $markup_app_passed>$prefix_app_passed</span>|;
  }
  output_gtk2_appointments($dialog->vbox, @apps);

  # Today's Appointments: Highlight "Today"
  @apps = @output_content_today;
  foreach (@apps) {
    # first escape markup characters
    markup_escape($_);
    # just replace text by hightlighted version
    s|^$prefix_app_today|<span $markup_app_today>$prefix_app_today</span>|;
  }
  output_gtk2_appointments($dialog->vbox, @apps);

  # Normal Appointments
  @apps = @output_content;
  foreach (@apps) {     markup_escape($_);    }   # mask all markup chars
  output_gtk2_appointments($dialog->vbox, @apps);

  # Connect signals and show Widget
  $dialog->signal_connect (response => \&gtk2_response);
  $dialog->show_all;
  Gtk2->main;
  $dialog->hide_all;
  print "DEBUG: Gtk2 Event loop exited, continuing program execution\n" if $options{'Debug'};
}


# format appointments and put into vbox for Gtk2-Widget as markup text label
# 1.P: vbox object
# 2.P: Array reference to Appointments
sub output_gtk2_appointments($\@) {

  # Get Parameters
  my $dialog_vbox = shift;
  my $aref = shift;

  # Debug
  # use Data::Dumper;
  # print Dumper($aref);

  if ( @{$aref} > 0 ) {           # We have to put some entries
    # Need to center entries; put them into another vbox (for later alignment)
    my $vbox = Gtk2::VBox->new(TRUE, 0);   # homogenious, no extra spacing

    foreach my $txt (@{$aref}) {
      $_ = Gtk2::Label->new();
      $_ -> set_markup($txt);
      # format the label
      $_ -> set_alignment(0, 0);      # Align left, top
      $_ -> set_selectable(TRUE);     # you can copy text from the label
      $vbox->add($_);  # put into inner vbox
    }

    # Align in the middle, do not take up more space then required
    my $align = Gtk2::Alignment->new(0.5, 0, 0, 1); # xalign, yalign, xscale, yscale
    $align->set_padding(0, 0, 10, 10);  # Pad 10px left and right
    $align->add($vbox);                 # And now add our vbox

    # Put into Dialog's Box
    $dialog_vbox->add($align);  # put in box

    # Add separator when required (i.e. when we put entries at all)
    $_ = Gtk2::HSeparator->new();
    $dialog_vbox->add($_);  # put in box
  }

}


# escape markup characters before applying pango markup in gtk2 label
# 1.P: Reference to Text which should be escaped
sub markup_escape(\$) {
  # *** Variables
  my $tref = shift;       # Ref to Text

  # Escape &
  $$tref =~ s/&/&amp;/g;
  # Escape <
  $$tref =~ s/</&lt;/g;
  # Escape >
  $$tref =~ s/>/&gt;/g;
  # Escape " --> not needed
  #  $$tref =~ s/"/&quot;/g;
  # Escape ; --> not needed
  #  $$tref =~ s/;//;

  # Debug
  # print "Escaped: $$tref\n";

}

# Attach cstermin icon to the handed over gtk2 window
# 1.P: window object
sub attach_gtk2_icon ($) {
  # Only try to load icon when file exists
  if (! -f $Icon_File) {
    print "DEBUG: Icon File \"$Icon_File\" not found\n" if $options{'Debug'};
    return;
  }

  # Now load icon
  $_[0] -> set_icon_from_file( $Icon_File );
}


# displays the collected error messages in this run
sub error_gtk2() {

  # do we have something to display?
  return unless $error_messages;

  # Init Gkt2 (double should do no harm)
  Gtk2->init;

  # *** Build Widget
  # using the Simplest: GtkMessageDialog.html
  my $dialog = Gtk2::MessageDialog->new(undef,
  					'destroy-with-parent',
  					'error',
  					'ok',
  					$error_messages
  				       );

  $dialog->signal_connect (response => \&gtk2_response);
  attach_gtk2_icon($dialog);  # Try to load Window's icon
  $dialog->show_all;
  Gtk2->main;
  $dialog->hide_all;
}



# Callback for all Dialogs
sub gtk2_response {
  my ( $widget, $response ) = @_;

  if ($response eq 100) {
    # do not modify config file anyways
    delete $options{'Modify'};
    print "DEBUG: Later clicked - not modifying the config file\n" if $options{'Debug'}; 

  }

  Gtk2->main_quit;  # quit in any way
  1;
}
