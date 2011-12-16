#!/usr/bin/perl -w
use strict;
use Getopt::Long;
use testall_inc;
use IO::CaptureOutput qw/capture_exec/;

my $VERSION = "1.10";

#############################################################################
# For the version information list, see the file JtrTestSuite.Manifest
#############################################################################

# EDIT this variable to properly setup the john-test-suite script
my $JOHN_PATH = "../john-1.7.9/john-1.7.9-a/run";
# NOTE, john built on Windows 'may' need this lines changed to "$JOHN_PATH/john.exe" IF the script will not run properly.
my $JOHN_EXE  = "$JOHN_PATH/john";
my $UNIQUE    = "$JOHN_PATH/unique";
my $quiet     = "";
my @types=();
my @nontypes=();
my @caps=();
my @johnUsageScreen=();
my @validFormats=();
my @tstdata;
my $showtypes=0, my $basepath=""; my $prelims=0;
my $last_line_len=0;
my $john_type="core";  # may be replaced with jumbo.  This will end up BEING a typex
my $error_cnt = 0, my $error_cnt_pot = 0;
  
###############################################################################
# MAIN
###############################################################################

parseArgs();
johnPrelims();
readData();
filterPatterns();
process();
cleanup();
if ($error_cnt == 0 && $error_cnt_pot == 0) {
	ScreenOutAlways ("All tests passed without error\n");
} else {
	my $s = "Some tests had Errors. ";
	unless ($error_cnt == 0) { $s = $s . "  $error_cnt errors"; }
	unless ($error_cnt_pot == 0) { $s = $s . "  $error_cnt_pot errors reprocessing the .POT files"; }
	ScreenOutAlways ("$s\n");
}


###############################################################################
# Here are all of the subroutines that get the job done
###############################################################################

###############################################################################
# parse our command line options.
###############################################################################
sub parseArgs {
	my $help = 0;
	GetOptions(
		'help|?',          => \$help,
		'quiet=s'          => \$quiet,
		'type=s'           => \@types,
		'nontype=s'        => \@nontypes,
		'showtypes'        => \$showtypes,
		'basepath=s'       => \$basepath,
		'prelims!'         => \$prelims,
		) || usage($JOHN_EXE);
	if ($help) { usage(); }
	if ($basepath ne "") { 
		$JOHN_PATH = $basepath;
		$JOHN_EXE  = "$JOHN_PATH/john";
		$UNIQUE    = "$JOHN_PATH/unique";		
	}
	setquiet($quiet);
}

###############################################################################
# see if we can find a string (i.e. grep) from the usage data
###############################################################################
sub grepUsage {
	foreach my $line(@johnUsageScreen) {
		if (index($line,$_[0]) ge 0) {
			return 1;
		}
	}
	return 0;
}

###############################################################################
# here we do prelim work.
###############################################################################
sub johnPrelims {
	if ( ! -d $JOHN_PATH ) {
		ScreenOutAlways("ERROR, the JOHN_PATH variable has to be setup properly for this script file to run.\n");
		exit;
	}
	if ( ! -f $JOHN_EXE )  {
		ScreenOutAlways("Error, the JOHN_EXE variable is not setup properly, or john was not built yet\n");
		exit;
	}
	
	# we store a ./john error string to this file.  We will use this data in several ways, later.
	system ("$JOHN_EXE >JohnUsage.Scr 2>&1");
	open(FILE, "<JohnUsage.Scr") or die $!;
	@johnUsageScreen = <FILE>;
	close(FILE);
	
	ScreenOutAlways("-------------------------------------------------------------------------------\n");
	ScreenOutAlways("- JtRTestSuite. Version $VERSION, Dec 15, 2011.  By, Jim Fougeron\n");
	ScreenOut("-\n");
	ScreenOutAlways("- Testing this build of john:\n");
	ScreenOutAlways("-     $johnUsageScreen[0]"); # note the line ends in a \n, so do not add one.
	ScreenOut("-\n");
	ScreenOut("- against many formats. Each test should find 1500 passwords.  A few do find a\n");
	ScreenOut("- smaller count, and when this is the case, this script does list this fact.\n");
	ScreenOut("- If a format shows fewer than 1500 values (and .pot CHK) found, and the format\n");
	ScreenOut("- is not one of them listed as the 'supposed to be less then 1500' formats, then\n");
	ScreenOut("- it is very likely this format has a problem within the current build of john.\n");
	ScreenOutAlways("--------------------------------------------------------------------------------\n");
	ScreenOut("\n");
	
	# now use the john error screen to determine if this is a jumbo john, or
	# a core john. Then use this data to figure out what formats ARE and are NOT
	# able to be run by this build (so we can later skip formats NOT built in
	# this build.  Also check for how to do -utf8 or -enc:utf8 (different syntax
	# in different builds of john.  Also certain extra options like -nolog may
	# be 'possible'.  We simply parse that screen (and also a john -sub:list to
	# get a list of dynamics, if we are in a jumbo), so we know HOW to proceed.
	
	ScreenOutVV("John 'usage' data is:\n");
	ScreenOutVV(@johnUsageScreen);

	# can we use -pot=./tst.pot ?
	if (grepUsage("--pot=NAME")) {
		push(@caps, "jumbo");
		push(@caps, "core");  # note, jumbo can do both CORE and JUMBO formats
		ScreenOut("John Jumbo build detected.\n");
	} else {
		push(@caps, "core");  # core john can ONLY do core formats.
		ScreenOut("John CORE build detected.  Only core formats can be tested.\n");
	}
	# load all the format strings we 'can' use.
	loadAllValidFormatTypeStrings();
	# can we use -nolog option
	if (grepUsage("--nolog")) {
		push(@caps, "nolog_valid");
		ScreenOutV("--nolog option is valid\n");
	}
	# can we use --config=./john.conf ?
	if (grepUsage("--config=FILE")) {
		push(@caps, "config_valid");
		ScreenOutV("--config=FILE option is valid\n");
	}
	# if the --field-sep=value valid? 
	if (grepUsage("--field-separator-char=")) {
		push(@caps, "field_sep_valid");
		ScreenOutV("--field-separator-char=C option is valid\n");
	}
	if (grepUsage("--pot=NAME")) {
		push(@caps, "local_pot_valid");
		ScreenOutV("--pot=NAME option is valid\n");
	}
	# can we use -enc:utf8, -enc:koi8r, etc.
	if (grepUsage("--encoding=NAME")) {
		push(@caps, "encode_valid");
		ScreenOutV("--encoding=NAME option is valid\n");
		if (grepUsage("--encoding=LIST")) {
			loadAllValidEncodings();
		} else {
			# 'hopefully' these are valid.
			push(@caps, "utf8", "cp1252", "cp1251", "koi8r", "cp437", "cp737", "cp850", "cp858", "cp866", "iso5559-1", "iso5559-15" );
		}
	}
	if (@types) {
		ScreenOutV("Types to filter on:\n");
		ScreenOutV(@types);
		ScreenOutV("\n");
	} else {
		@types = ("*"); # we want ALL that are valid.
	}
	if (@nontypes) {
		ScreenOutV("Types to filter off (non-types):\n");
		ScreenOutV(@nontypes);
		ScreenOutV("\n");
	}
	ScreenOutV("Capabilities in this build of john:\n");
	ScreenOutV(@caps);
	ScreenOutV("\n");
}

###############################################################################
# we parse the JohnUsage.Scr file, for the --format=NAME line, and ALL lines
# up to the next param. We then chop out all of the 'valid' formats which this
# build of john claims to be able to handle.  Then we can later compare when
# running, and simply about a run, if this build does not support it.
# The format of this data is:
#  --format=NAME        force hash type NAME: des/bsdi/md5/bf/afs/lm/trip/
#                       dummy
# NOTE, there may be MANY more.   the format names have varied in case, from
# version to version.  We lowercase them here (and also in the input data file).
###############################################################################
sub loadAllValidFormatTypeStrings {
	my $in_fmt=0;
	my $fmt_str="";
	foreach my $line(@johnUsageScreen) {
		if ($in_fmt == 0) {
			if (index($line, "--format=NAME") == 0) {
				$in_fmt = 1;
				while (substr($line, 0, 1) ne ":") {
					$line = substr($line, 1, length($line)-1);
				}
				$line = substr($line, 2, length($line)-2);				
				chomp($line);
				$line =~ s/\r$//;  # strip CR for non-Windows
				$fmt_str = $fmt_str . $line;
			}
		} else {
			if (index($line, '-') == 0) { last; }
			while (substr($line, 0, 1) eq " " || substr($line, 0, 1) eq "\t") {
				$line = substr($line, 1, length($line)-1);
			}			
			chomp($line);
			$line =~ s/\r$//;  # strip CR for non-Windows
			$fmt_str = $fmt_str . $line;
		}
	}
	# Ok, now if we have 'dynamic's, LOAD them
	if (grepUsage("--subformat=LIST")) {
		system ("$JOHN_EXE --subformat=LIST >JohnDynaUsage.Scr 2>&1");
		open(FILE, "<JohnDynaUsage.Scr") or die $!;
		my @dyna = <FILE>;
		close(FILE);
		unlink("JohnDynaUsage.Scr");
		foreach my $line (@dyna) {
			my @ar = split(/ /, $line);
			if (index($ar[2], "dynamic_") == 0) {
				$fmt_str = $fmt_str . "/" . $ar[2];
			}
		}
	}
	
	@validFormats = split(/\//, $fmt_str);
	if ($quiet eq 'vv') {
		my $cnt = @validFormats;
		ScreenOutVV("There are $cnt formats this john build can handle are:\n");
		foreach my $line(@validFormats) { ScreenOutVV($line . ","); }
		ScreenOutVV("\n");
	}
}
sub loadAllValidEncodings {
	ScreenOutV("--encoding=LIST is valid, so we get valid encodings from there\n");
	system ("$JOHN_EXE --enc:LIST >JohnEncUsage.Scr 2>&1");
	open(FILE, "<JohnEncUsage.Scr") or die $!;
	my @encodings = <FILE>;
	close(FILE);
	unlink("JohnEncUsage.Scr");
	my $str; 
	foreach my $sline (@encodings) {
		if (index($sline, "Supported ") lt 0) {
			my @encline = split(/, /,$sline);
			foreach my $item (@encline) {
				if (index($item, " ") gt 0) {
					$item = substr($item, 0, index($item, " "));
				}
				if (index($item, ",") gt 0) {
					$item = substr($item, 0, index($item, ","));
				}
				push(@caps, $item);
			}
		}
	}
}
###############################################################################
# we read the data file 'tstall.dat'.  This is a CSV file. It contains lines
# of data, which provide the data, used along with john's capabilities, along
# with the way the user wants to run (the -type and -nontype values).
###############################################################################
sub readData {
	open(FILE, "<tstall.dat") or die $!;
	my @lines = <FILE>;
	close(FILE);
	foreach my $line(@lines) {
		chomp($line);
		$line =~ s/\r$//;  # strip CR for non-Windows
		if (length($line) > 0 && substr($line, 0, 1) ne "#") {
			$line = "(*)" . $line;
			push(@tstdata, $line);
		}
	}
	if ($quiet eq 'vv') {
		my $cnt = @tstdata;
		ScreenOutVV("Running data-dictionary. $cnt items (tstall.dat):\n");
		foreach my $line(@tstdata) { ScreenOutVV($line . "\n"); }
		ScreenOutVV("\n");
	}
}
###############################################################################
###############################################################################
sub filterPatterns {
	my @filtereddata;
	{
		LINE: foreach my $line(@tstdata) {
			my @ar = split(',', $line);
			my $cnt = @ar;
			my $valid = 'f';
			if ($cnt == 12) {
				# determine if our build of john 'can' do this format:
				if (!stringInArray($ar[7], @validFormats)) { 
					ScreenOutVV("Line [$line] filtered out, because format ${ar[7]} can not be processed by this build of john\n");
					next LINE;
				}
				# Now, make sure that this is something 'requested'
				if (!arrayPartInString($ar[0], @types)) { 
					ScreenOutVV("Line [$line] filtered out, no requests [$ar[0]] in [@types] were satisfied\n");
					next LINE;
				}
				# Now, make sure that nothing from the is something 'non-requested' is set
				if (arrayPartInString($ar[0], @nontypes)) { 
					ScreenOutVV("Line [$line] filtered out. A non request [@types] was found\n");
					next LINE;
				}
				# Now, make sure that ALL of the required types are satisfied.
				# NOTE, if user specified a format, then assume all requirements have also been specified.
				if (!stringInArray($ar[7], @types)) {
					if ($ar[1] ne "(X)") {
						my @reqs = split(/&/,$ar[1]);
						$valid = 'f';
						foreach my $req(@reqs) { # note, these are already wrapped in ()
							if (!stringInArray(substr($req, 1, length($req)-2), @types)) { 
								ScreenOutVV("Line [$line] filtered out, required option [@reqs] not satisfied in [@types]\n");
								next LINE;
							}
						}
					}
				}
				# Now, make sure that ALL of the required build capacities are satisfied.
				my @reqs = split(/&/,$ar[2]);
				foreach my $req(@reqs) {
					if (!stringInArray(substr($req, 1, length($req)-2), @caps)) { 
						ScreenOutVV("Line [$line] filtered out, required build option option [@reqs] not satisfied in [@caps]\n");
						next LINE;
					}
				}
				
				# OK, make sure the dictionary file 'exists'
				unless (-e "${ar[5]}.dic") { 
					ScreenOutVV("Line [$line] filtered out, because dictionary ${ar[5]}.dic not found\n");
					next LINE;
				}

				# we are going to process this item.  Add it to our filtered array.
				push (@filtereddata, $line);
			}
		}
		
		# now that we have filtered our data, put it on the 'real' list.
		@tstdata = ();
		for my $line(@filtereddata) { push(@tstdata, $line); }
	}
	
	if ($quiet eq 'vv') {
		my $cnt = @tstdata;
		ScreenOutVV("Filtered items from the data-dictionary. $cnt items (tstall.dat):\n");
		foreach my $line(@tstdata) { ScreenOutVV($line . "\n"); }
		ScreenOutVV("\n");
	}
	
}
###############################################################################
###############################################################################
sub process {
	my $pot = "./tst.pot";
	my $cmd_head = "$JOHN_EXE -ses=./tst";
	if (stringInArray("nolog_valid", @caps)) { $cmd_head = "$cmd_head -nolog"; }
	#if (stringInArray("config_valid", @caps)) { $cmd_head = "$cmd_head -config=./john.conf"; }
	if (stringInArray("local_pot_valid", @caps)) { $cmd_head = "$cmd_head -pot=./tst.pot"; }
	else {
		# handle john 'core' behavior.  We save off existing john.pot, then it is overwritten
		unlink $JOHN_PATH."/john.ptt";
		rename $JOHN_PATH."/john.pot",$JOHN_PATH."/john.ptt";
		$pot = $JOHN_PATH."/john.pot";
	}
	my $dict_name_ex = "";
	my $dict_name = "";
	my $line = "";
	
	LINE: foreach my $line(@tstdata) {
		my @ar = split(',', $line);
		$dict_name = "$ar[5].dic";
		my $cmd = "$cmd_head $ar[6]";
		unless (-e $ar[6]) { next LINE; } 
		if ($ar[3] != 10000) {
			open (FILE, "<".$dict_name);
			my @lines = <FILE>;
			close(FILE);
			$dict_name = "$ar[5]-$ar[3].dic";
			$dict_name_ex = $dict_name;
			open (FILE, ">".$dict_name);
			my $i;
			for ($i = 0; $i < $ar[3]; $i += 1) {
				my $line = shift(@lines);
				print FILE $line;
			}
			close(FILE);
		}
		$cmd = "$cmd -w=$dict_name";
		
		if ($ar[8] eq 'Y') { $cmd = "$cmd \'-form=$ar[7]\'"; }
		if ($ar[9] ne 'X') { $cmd = "$cmd $ar[9]"; }
		$cmd = "$cmd 2>&1 >/dev/null";
		
		ScreenOutVV("Execute john: $cmd\n");
		unlink($pot);
		my $cmd_data = `$cmd`;
		ScreenOutVV("\n\nCmd_data = \n$cmd_data\n\n");
		
		my @crack_cnt = split (/\n/, $cmd_data);

		my @crack_xx = ();
		foreach $line (@crack_cnt) {
			if (index($line, "guesses: ") eq 0) {
				@crack_xx = split (/ /, $line);
				last;
			}
		}
		while (not defined $crack_xx[1]) { push (@crack_xx, "0"); }
		my $orig_crack_cnt = $crack_xx[1];
		ScreenOutSemi("\n");
		
		if (index($ar[10], "($orig_crack_cnt)") lt 0) {
			while (not defined $crack_xx[4]) { push (@crack_xx, "unk"); }
			my $str = sprintf("form=%-28.28s guesses: %4.4s $crack_xx[3] $crack_xx[4] : Expected count(s) $ar[10]  [!!!FAILED!!!]\n", $ar[4], $orig_crack_cnt);
			ScreenOutAlways($str);
			# check for self-test failure
			$error_cnt += 1;
			foreach $line (@crack_cnt) {
				if (index($line, "Self test failed") ge 0) {
					ScreenOutAlways("$line\n");
				}
			}
		} else {
			my $str = sprintf("form=%-28.28s guesses: %4.4s $crack_xx[3] $crack_xx[4]  [PASSED]\n", $ar[4], $orig_crack_cnt);
			ScreenOutSemi($str);
		}
		if ($dict_name_ex ne "") {
			unlink ($dict_name_ex);
		}
		
		# now do the .pot check.
		unlink ("pw3");
		if ($ar[8] eq "\'-fie=\\x1F\'") {
			my $cmd2 = sprintf("cut -f 2-8 -d \"%c\" < $pot | $UNIQUE pw3 > /dev/null", 31);
			system($cmd2);
		} else {
			my $cmd2 = sprintf("cut -f 2-8 -d \":\" < $pot | $UNIQUE pw3 > /dev/null");
			system($cmd2);
		}
		$cmd =~ s/$dict_name/pw3/;
		
		ScreenOutVV("Execute john (.pot check): $cmd\n");		
		unlink ($pot);
		$cmd_data = `$cmd`;
		ScreenOutVV("\n\nCmd_data = \n$cmd_data\n\n");
		
		unlink("pw3");
		@crack_xx = ();
		@crack_cnt = split (/\n/, $cmd_data);
		foreach $line (@crack_cnt) {
			if (index($line, "guesses: ") eq 0) {
				@crack_xx = split (/ /, $line);
				last;
			}
		}
		while (not defined $crack_xx[1]) { push (@crack_xx, "0"); }
		while (not defined $crack_xx[4]) { push (@crack_xx, "unk"); }
		if (index($ar[11], "($crack_xx[1])") lt 0 && $crack_xx[1] ne $orig_crack_cnt) {
			my $str = sprintf(".pot CHK:%-24.24s guesses: %4.4s $crack_xx[3] $crack_xx[4] : Expected count(s) $ar[11]  [!!!FAILED!!!]\n", $ar[4], $crack_xx[1]);
			ScreenOutAlways($str);
			$error_cnt_pot += 1;
		} else {
			my $str = sprintf(".pot CHK:%-24.24s guesses: %4.4s $crack_xx[3] $crack_xx[4]  [PASSED]\n", $ar[4], $crack_xx[1]);
			ScreenOutSemi($str);
		}
	}
	ScreenOutSemi("\n");
	if (!stringInArray("local_pot_valid", @caps)) {
		# handle john 'core' behavior.  then we delete the pot we just made, then rename the 'saved' version.
		unlink $JOHN_PATH."/john.pot";
		rename $JOHN_PATH."/john.ptt",$JOHN_PATH."/john.pot";
	}	
}

###############################################################################
# cleanup temp files, etc
###############################################################################
sub cleanup {
	unlink ("JohnUsage.Scr");
	unlink ("tst.pot");
	unlink ("tst.log");
	unlink ("tst.ses");
}