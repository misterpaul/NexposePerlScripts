#! /usr/bin/perl
# to do: credits, POD
# perl -d GroupMaker.pl --host=vulnscan01.llbean.com --port=443 --user=GroupMaker --debug --rotate=1
# nexpose-groupmaker
use strict;
use warnings;

require HTTP::Request;
require LWP::UserAgent;
use XML::Simple;
use Data::Dumper;
use Term::ReadKey;                          # to allow us to read password w/out echo'ing results
use Log::Log4perl qw(:easy);
use Getopt::Long;
use Pod::Usage;


# Initialize variables to defaults(g indicates used globally)
my $man = 0;
my $help = 0;
my $host = '';
my $port = '';
my $userid = '';
my $password = '';
my $logfile = 'groupmaker.log';
my $g_xml;
my $g_session;
my $g_log;
my $g_rebuild = 0;
my $g_today = scalar localtime();
my $debug = 0;
my $rotatelogs = 0;
my $maxdepth = 25; # how deep we let the recursion go when we're determining rebuild order

# Get command-line options
 my $getoptions = GetOptions (
	"logfile=s"		=> \$logfile,
	"debug"			=> \$debug,
	"host=s"		=> \$host,
	"port=i"		=> \$port,
	"user=s"		=> \$userid,
	"pass=s"		=> \$password,
	"rotate=i"		=> \$rotatelogs,
	"rebuild"		=> \$g_rebuild,
	'help|?'		=> \$help, 
	'man'			=> \$man) or pod2usage(2);	
	# need to add help

# handle help
pod2usage(1) if $help;
pod2usage(-exitstatus => 0, -verbose => 2) if $man;

# rotate the log if needed
my $rotateResults;
$rotateResults = rotatelog($logfile, $rotatelogs) if ($rotatelogs);

# set up logging
$ENV{'PERL_LWP_SSL_VERIFY_HOSTNAME'} = 0;
my $loglevel = $debug ? $DEBUG : $INFO;
Log::Log4perl->easy_init( { level   => $loglevel,
                            file    => ">>$logfile" } );

# if we rotated the logs, log the results
if ($rotatelogs) {
	foreach my $result (@$rotateResults) {
		INFO($result);
	}
}

unless ($g_rebuild) {
	print <<HEADER;
**************************************************************************
* GroupMaker - please run GroupMaker.pl --man for complete info on use. *
**************************************************************************
HEADER

	$host = askIfEmpty ("Please enter the hostname where Nexpose runs:", $host);
	$port = askIfEmpty ("Please enter the port for Nexpose (most installs use 3780):", $port);
	$userid = askIfEmpty ("Please enter your Nexpose username:", $userid);
	$password = askIfEmpty ("Please enter your Nexpose password:", $password, 1);
	print "\n";
}

# Create a new XML:Simple object for parsing the XML response from NeXpose.
$g_xml = new XML::Simple;

# Login and create a NeXpose session
DEBUG("Attempting login to " . $host);
my $ua = LWP::UserAgent->new;
my $response = &sendXmlRequest($ua, '<LoginRequest user-id="' . $userid . '" password="' . $password . '"/>');

if ($response->content=~/session-id="(.+)"/)
{
   $g_session = $1;

	INFO("Login Successful with Session ID: " . $g_session);

	dothework ();
#   Logout of NeXpose session
    my $response = &sendXmlRequest($ua, '<LogoutRequest session-id="' . $g_session . '"/>');
    #print "Logout Successful \n\n";
    INFO("Logout Successful");
}
 else
 {
	ERROR ("Login Failed.");
	DEBUG ("Response: " . $response->as_string);
 }

sub dothework {

	# Get a list of groups.  this assumes group names are unique.
    my $response = &sendXmlRequest($ua, '<AssetGroupListingRequest session-id="' . $g_session . '"/>');
	my $groupList = $g_xml->XMLin($response->content, KeyAttr=>['name'], ForceArray=>['AssetGroupSummary'])->{AssetGroupSummary};

	# get the groups to rebuild and determine the order if rebuilding
	my $buildGroups;
	my $buildDetails;
	if ($g_rebuild) {
		($buildGroups, $buildDetails) = getRebuildGroups($groupList);
	} else {
		$buildGroups = ['-1']; # just a placeholder
	}

	foreach my $groupId (@$buildGroups) {
		# loop until we have a valid command (aka rule)
		my $command = "\nREPEAT";
		my $orig_cmd;  # we tweak the command in the process. this stores the original.
		my $groupInfo;
		while ($command eq "\nREPEAT") {
			if ($g_rebuild) {
				$command = $buildDetails->{$groupId}->{'rule'};
			} else {
				# ask the user for the command
				$command = getCommand($groupList);
			}
			$orig_cmd = $command;

			# handle MATCH() - convert it into a string of ORs
			if ($command =~ /^\s*I?MATCH/i) {
				$command = domatch($command, $groupList);
			}
		}
		
		unless ($command eq "\nQUIT") {
			if ($g_rebuild) {
				$groupInfo = $buildDetails->{$groupId};
			} else {
				# ask the user for the group info
				$groupInfo = getNewInfo($orig_cmd); 
			}
			unless ($groupInfo->{'quit'}) {
				# get the devices for our new group
				my @devices = dologic($command, $groupList);
				# create
				createGroup($groupId, $groupInfo, \@devices);
			}
		}
	}
}

sub sendXmlRequest
{
   my ($ua, $xml) = @_;

   my $url = 'https://' . $host . ':'.$port.'/api/1.1/xml';
   my $request = HTTP::Request->new(POST => $url);
   $request->content_type('text/xml');
   $request->content($xml);
   my $response = $ua->request($request);
   if ($response->content=~/success="0"/)
   {
      unless ($g_rebuild) {
		print "\n\nRequest failed => " . $response->content . "\n\n";
	  }
      ERROR("Request failed => " . $response->content );
   }
   
   return $response;
}

sub createGroup {
	my $groupId = shift;
	my $groupInfo = shift;
	my $devices = shift;

	# create the devices
	my $devxml;
	foreach my $dev (@$devices) {
		$devxml .= qq(<device id="$dev"></device>);
	}

	# Create a group
	my $req = <<REQUEST;
<AssetGroupSaveRequest session-id="$g_session">
	<AssetGroup id="$groupId" name="$groupInfo->{'name'}" description="$groupInfo->{'desc'}">
		<Devices>
			$devxml
		</Devices>
	</AssetGroup>
</AssetGroupSaveRequest>
REQUEST

	my $msg = "Creating group $groupInfo->{'name'}...\n";
	DEBUG($msg . $req);
	unless ($g_rebuild) {
		print $msg;
	}
	# run the request 
    $response = &sendXmlRequest($ua, $req);
	DEBUG ($response->content);
	if ($response->content=~/success="1"/ and !$g_rebuild) {
		print "Group created successfully\n";
	}

}

sub getCommand
{
	# ask user to create a group of groups
	my $groupList = shift;
	my @groups = sort keys %$groupList;

	
	# print the list, incrementing the index (for human use) and spacing nicely
	my $grouplist = join("\n", map {"    ( " . $groupList->{$_ }->{'id'}  . " )\t" . $_} @groups);

	print <<INSTRUCTIONS;

   Group Id	Group Name
   --------	--------------------------------------------------
$grouplist

 Define your group of groups by using the Group Ids above and logic
 statements. You can use AND, OR, NOT, and parentheses.

 Or, use MATCH() or IMATCH() to select all the groups that match a
 regular expression. (MATCH() and IMATCH() can not be used with group
 numbers or logic statements.)  When using MATCH & IMATCH, be sure
 to escape and special characters (pretty much anything that isn't
 a number or letter) with a backslash \ if they are a part of the 
 search string.

 Keep it simple. You can build more complex groups by making groups of 
 these groups.

 SAMPLES:
 1 OR 2 OR 3
    -- this group will have everything from 1, 2, & 3

 (1 OR 2 OR 3) AND NOT 4
    -- this group will have everything from 1, 2, & 3, as long
       as it is not in 4

 (1 AND 2) 
    -- this group will have everything that appears in both 1 & 2 

 MATCH(^devices)
    -- this group will have everything that is in any group whose name begins
       with "devices"

 IMATCH(^devices)
    -- same as above, but case-independent.

Define your group of groups here: 
INSTRUCTIONS
	my $cmd = <STDIN>;
	chomp $cmd;
	DEBUG ("Entered command: $cmd");

	# validate.  only allow numbers, parenthesis, spaces, AND, OR, NOT or MATCH (at the beginning)
	# validate by stripping those out. if anything left, error.
	my $failmatch = $cmd;
	my $failothers = $cmd;
	$failmatch =~ s/^I?MATCH\s*\(.*\)\s*//i;
	$failothers =~ s/\d+|\(|\)| AND | OR |NOT //ig;
	$failothers =~ s/\s*//g;   # strip out the spaces after the words to force them to have spaces
	if ($failmatch and $failothers) {
		# something left over! oops!
		my $msg = "\nOOPS! Invalid definition. Use only numbers, parenthesis, spaces, AND, OR, NOT, and MATCH().";
		DEBUG($msg);
		print "$msg\n";
		print "Hit <ENTER> to try again or type QUIT (plus <ENTER>) to exit.";
		my $continue = <STDIN>;
		if ($continue =~ /quit/i) {
			$cmd = "\nQUIT";
			INFO ("User quit.");
		} else {
			$cmd = "\nREPEAT";
		}
	} else {
		DEBUG("Command looks valid: $cmd");
	}
	return $cmd;
}

sub domatch {
	# convert a MATCH or IMATCH to a list of groups 
	# returns a list of groups joined by OR
	# OR returns \nREPEAT or \nQUIT (names can't have \n in them)
	my $command = shift;
	my $groupList = shift;
	my @groups = sort keys %$groupList;
	my $response;

	INFO ("Convert to logic: $command");

	my $cmd = $command;
	# determine if IMATCH
	my ($imatch) = $cmd =~ /IMATCH/i;
	# remove MATCH( ) or IMATCH( )
	$cmd =~ s/^\s*I?MATCH\s*\((.*)\s*\)\s*/$1/i;
	DEBUG ("Stripped out (I)MATCH and extra spaces: $cmd");
	
	my @matches;
	if ($imatch) {
		@matches = grep { /$cmd/i } @groups;
	} else {
		@matches = grep { /$cmd/ } @groups;
	}
	INFO ("Matched groups: " . join ("; ", @matches));

	my $ynq = "y";  # default to yes for the non-interactive. interactive can override
	unless ($g_rebuild) {
		print "\n\n";
		if (@matches) {
			print qq("$command" matched the following groups:\n\t);
			print join ("\n\t", @matches);
		} else {
			print qq("$command" failed to match any groups.\n);
		}
		$ynq = ynq("\n\nContinue to build this group? (no = try again)");
		if ($ynq eq "q") {
			INFO ("User quit before building group");
			@matches = ();
			$response = "\nQUIT";
		} elsif ($ynq eq "n") {
			DEBUG ("User will try again");
			@matches = ();
			$response = "\nREPEAT";
		}
	}

	# if we're continuing, build the logic statement
	if ($ynq eq "y") {
#		my @group_nums;
#		for (my $i = 0;$i <@$groups_ref ;$i++) {
#			foreach my $m (@matches) {
#				if ($m eq $$groups_ref[$i]) {
#					push (@group_nums, $i);
#					last; #last breaks the innermost loop
#				}
#			}
#		}
		$response = join (" OR ", map {$groupList->{$_}->{'id'}} @matches);
	}
	return $response;
}

sub ynq {
	# Yes, No, Quit
	# defaults to no
	my $prompt = shift;
	print $prompt . "\n";
	print "Please enter Yes, No, or Quit (y,n,q):";
	my $ynq = <STDIN>;
	my $ret = "n";
	if ($ynq =~ /y/i) {
		$ret = "y";
	} elsif ($ynq =~ /q/i) {
		$ret = "q";
	}
	return $ret;
}

sub uniquelist {
	# converts a list into a list where each item appears only once
	# order is not guaranteed
	# clumsy, but understandable
	my %hash;
	foreach my $item (@_) {
		$hash{$item}=1;
	}
	return (keys %hash);
}

sub dologic {
	# this is the heart of the program. It takes the command, grouplist, and groups array,
	# and returns a list of devices for the new group
	my $command = shift;
	my $groupList = shift;

	# need a unique list of these numbers. 
	my @groupIds = uniquelist($command =~ /\d+/g);
	
	# find all the devices in those groups. create a list of the devices
	my $allDevices = {}; 
	foreach my $gid (@groupIds) {

		# get the details from group 
		$response = &sendXmlRequest($ua, '<AssetGroupConfigRequest session-id="' . $g_session . '" group-id="' . ($gid) . '"/>');
#		my $groupConfig = $g_xml->XMLin($response->content, ForceArray=>['Devices','devices', 'id'])->{AssetGroup};
		my $groupConfig = $g_xml->XMLin($response->content, KeyAttr=>[], ForceArray=>['device'])->{AssetGroup};
	
		# walk through the devices
		foreach my $d_hash (@{$groupConfig->{'Devices'}->{'device'}}) {
			my $d = $d_hash->{'id'};
			$allDevices->{$d}->{$gid} = 1;
		}
	}

	# now, go through all devices, and determine if they are in our new group
	my @newGroup; # list of all device id's in new group

	# if there are ONLY or's, we can skip this and just return the list of all devices
	if (onlyOrs($command)) {
		@newGroup = keys %$allDevices;
	} else {
		# stick a space at the beginning & end of the cmd so all numbers or words have spaces
		$command = " " . $command . " "; 
		$command =~ s/\(/ ( /g;
		$command =~ s/\)/ ) /g;
		foreach my $device (keys %$allDevices) {
			my $cmd = $command;
			# convert group ids to 1 if we have it
			foreach my $gid (keys %{$allDevices->{$device}}) {
				$cmd =~ s/\s$gid\s/ =1= /g;  # the = keep us from deleting the 1 in the next line
			}
			# convert remaining group ids to 0
			$cmd =~ s/\s\d+\s/ 0 /g;

			# remove the markers
			$cmd =~ s/=//g;

			# lowercase any words
			$cmd = lc($cmd);

			# convert not to !
			$cmd =~ s/not/\!/g;

			#evaluate the logic
			DEBUG ("evaluating device $device: $cmd");
			my $toInclude = eval($cmd);
			DEBUG ("result: $toInclude");

			push (@newGroup, $device) if ($toInclude);
		}
	}
	return @newGroup;
}

sub onlyOrs {
	# check to see if we only have ors
	my $cmd = shift;
	$cmd =~ s/\s*|(OR)*|\d*//g;
	return $cmd eq "";
}

sub getNewInfo {
	# get the info to create the group
	my $cmd = shift;
	my $info = {};
	print "\nNow, provide the details about the group we're going to create.\n";
	print "Group Name:";
	$info->{'name'} = <STDIN>;
	chomp $info->{'name'};

	print "\nDescription:";
	$info->{'desc'} = <STDIN>;
	chomp $info->{'desc'};
	# add a space if user entered anything in the description
	$info->{'desc'} .= $info->{'desc'} ? " " : "";

	my $rebuild = "Rebuild=";
	my $ynq = ynq("\nDo you want to rebuild this group whenever GroupMaker is run with --rebuild?");
	if ($ynq eq "y") {
		$rebuild .= "On";
	} elsif ($ynq eq "n") {
		$rebuild .= "Off";
	} else {
		$info->{'quit'} = 1;  # we'll check this when we're done
		INFO ("User selected to quit.");
	}

	# add information about this script to the desc
	$info->{'desc'} .= "(This group was created by the GroupMaker script. Rule='$cmd'. $rebuild. First created: $g_today.)";
	
	# validation checks would be good, but I don't know what is legal in Nexpose
	return $info;

}

sub askIfEmpty {
	# asks user for info if field is empty and we're in interactive mode
	my $question = shift;
	my $answer = shift;
	my $hide = shift;  # set true to mask the answer
	if (! $g_rebuild and ! $answer ) {
		print "\n$question";
		print " (Note: No characters will be displayed.)" if ($hide);
		ReadMode("noecho") if ($hide);
		$answer = <STDIN>;
		ReadMode("restore") if ($hide);
		chomp $answer;
	}
	return $answer;
}

sub rotatelog {
	# rotate the log if it is over logsize (in MB)
	my $logfile = shift;
	my $logsize = shift;
	my $results = []; # can't log results while rotating!
	my $continue = 1; # used for checking to see if we keep going

	my $oldfile = $logfile . ".old";
	if (-e $logfile and ((-s $logfile) > $logsize*1024*1024)) {
		# we need to rotate files
		push @$results, "Need to rotate $logfile.";
		# (1) If a file exists with the same name as the logfile plus .old (eg groupmaker.log.old), delete it.
		if (-e $oldfile) {
			if (unlink($oldfile) == 0) {
				# file deleted. proceed.
				push @$results, "Deleted $oldfile";
			} else {
				push @$results, "Could not delete $oldfile: $!";
				$continue = 0;
			}
		}

		# (2) rename the logfile, adding .old to the end.
		if ($continue and rename ($logfile, $oldfile) != 0) {
			push @$results, "Moved $logfile to $oldfile";
		} else {
			push @$results, "Could not move $logfile to $oldfile: $!";
		}
	}

	return $results;
}

sub getRebuildGroups {
	# returns a list of all the groups that need to be rebuilt, in the order they need to be rebuilt
	# also returns the details for rebuilding
	my $groupList = shift;
	my $rebuildDetails; # group-id => {'rule'=>rule, 'desc'=>new_desc, 'name'=>name} 
	my @matches;  # groups that are MATCH or IMATCH (we do these last)

	# dependency tree components: (parents depend on children in this case)
	my $predecessors;		# group->list of groups it depends on (must be built before)
	my $successors;   # group->list of groups dependent on it (must be built after)
	my $datematch = qr([A-Z][a-z][a-z] [A-Z][a-z][a-z] \d\d? \d\d:\d\d:\d\d \d\d\d\d);

	# do the analysis
	foreach my $groupName (keys %$groupList) {
		my $desc = $groupList->{$groupName}->{'description'};
		my $id =   $groupList->{$groupName}->{'id'};
		my ($prefix, $rule, $rebuild, $birthday, $suffix) = 
			$desc =~ /(.*\(This group was created by the GroupMaker script\. Rule\=\')(.*)(\'\. Rebuild\=(?:Off|On).)( First created: $datematch)(?:\. Rebuilt: $datematch)?(\.\).*)/;
		
		if ($rebuild and ($rebuild =~ /On/)) {
			my $newDesc = $prefix . $rule .  $rebuild . $birthday . ". Rebuilt: $g_today" . $suffix;
			$rebuildDetails->{$id}->{'name'} = $groupName;
			$rebuildDetails->{$id}->{'rule'} = $rule;
			$rebuildDetails->{$id}->{'desc'} = $newDesc;

			# check for dependencies & (I)MATCH
			if ($rule =~ /MATCH/i) {
				push @matches, $id;
			} else {
				# get the groups it depends on (groups that must go before me)
				my @groups = $rule =~ /(\d+)/g;
				$predecessors->{$id} = \@groups;
				# now list it as dependent on each one (I am a successor to each of these)
				foreach my $predecessor (@groups) {
					if ($successors->{$predecessor}) {
						push @{$successors->{$predecessor}}, $id;
					} else {
						$successors->{$predecessor} = [$id];
					}
				}
			}
		}
	}
	# now, figure out the rebuild order (depenency tree)
	my $done;			# keep track of groups as we add them to the list

	my @list = keys %$predecessors;
	my $reverseGroups = [];
	reverseOrderThem(\@list, $reverseGroups, $done, $successors, $maxdepth, 0);
	

	return [reverse (@$reverseGroups), @matches], $rebuildDetails;
}

sub reverseOrderThem {
	my $list = shift;
	my $results = shift;
	my $done = shift;
	my $successors = shift;
	my $maxdepth = shift;
	my $depth = shift;
	$depth++;
	if ($depth > $maxdepth) {
		ERROR("Excessive recursion trying to determine rebuild order. Recursion exceeded $maxdepth. Exiting.");
		die "Excessive recursion trying to determine rebuild order. Recursion exceeded $maxdepth. Exiting.";
	}
	foreach my $id (reverse sort @$list) { # go through the list in reverse order b/c bigger ids probably depend on smaller ids (created earlier)
		if ($done->{$id}) {
			# i am done already, do nothing.
		}else {
			if ($successors->{$id}) {
				# order all my successors
				reverseOrderThem($successors->{$id}, $results, $done, $successors, $maxdepth, $depth);
			}
			# Now all my successors are done, add me and mark me done
			push @$results, $id;
			$done->{$id} = 1;
		}
	}
}

sub getNewGroupDetails {
	# returns a buildDetails hash
	my $rebuildDetails; # group-id => {'rule'=>rule, 'desc'=>new_desc, 'name'=>name} 


}

=pod

=head1 NAME

GroupMaker - A script for creating groups of groups in Nexpose to create complex Asset Groups.

=head1 SYNOPSIS

perl GroupMaker.pl --user=myname --host=nexpose.acme.com --port 3780

perl GroupMaker.pl --rebuild

=head1 DESCRIPTION

I wish Nexpose had the ability to create groups of groups. That is,
you might need a group that was everything in Group A, Group B, but
not in Group C. I am writing GroupMaker to address this need.

When you create groups with a script (using the API), you can only
create static groups.  Therefore GroupMaker creates static groups.
Once you create a group, its members stay the same until you change
the group.  To address this inability to create dynamic groups,
GroupMaker has a "rebuild" mode, which will recreate all the groups
you have saved. If you schedule GroupMaker to automatically run
in rebuild mode (perhaps daily), your groups won't be truly dynamic,
but they will at least be as current as the last time GroupMaker ran.

=head1 OPTIONS

=over 4

=item --rebuild 

Rebuilds all the groups that are set to Rebuild=On. It runs in a non-interactive manner. Therefore, you must also set user, pass, host, and port, either in the command line or by editing the script.
Rebuilding a group defined by MATCH or IMATCH will re-run the match, so if a group was added or deleted, results may change. Also, there is no easy way to predict the correct order to rebuild matches (if one matched group depends on another matched group), so results could be off.
Rebuilding a group defined by Group Ids will fail if one of the groups in the definition was deleted. The rebuilt group will have no devices.

You may wish to run with --rebuild before running interactively to make sure your groups are up to date.

GroupMaker analyzes the dependencies among groups of groups and rebuilds them in the proper order.  One exception: it does not yet do this for 
groups defined with MATCH or IMATCH.  I intend to fix that soon.

=item --logfile=filename.log 

Sets the log file to filename.log. By default, the logfile is "groupmaker.log"

=item --user=username 

Sets the username. You can edit the script to hard-code this if you wish.

=item --pass=password 

Sets the password. You can edit the script to hard-code this if you wish.

=item --host=hostname 

Sets the Nexpose host to connect to.  You can edit the script to hard-code this if you wish.

=item --port=port_number

Sets the port used by Nexpose (most systems use 3780).  You can edit the script to hard-code this if you wish.

=item --rotate=log_size 

Rotates any log files larger than log_size (in MB).  

The script uses a very simplistic log rotation: 

=over 4

=item (1) 

If a file exists with the same name as the logfile plus .old (eg groupmaker.log.old), delete it.

=item (2) 

If a file exists with the name of the logfile, rename it, adding .old to the end.

=back

If you need anything more sophisticated, write it yourself, or use an external tool to do it.

=back

=head1 LOGGING

All results are logged to groupmaker.log unless overridden by --logfile. 

=head1 AUTHENTICATION & AUTHORIZATION

NOTE: This script appears to need Nexpose full admin rights in order to rebuild groups. I believe this is a bug in Nexpose
and will report it. So, until this is resolved, it looks like you need to disregard the info below and run as an administrator, at least for rebuilding groups 

The account used to run this script SHOULD only need the following permissions in Nexpose:

Roles - set to custom:

=over 4

=item *

Manage Dynamic Asset Groups (this might not be necessary, but it ensures the user can access all sites)

=item *

Manage Static Asset Groups

=item *

View Group Asset Data

=item *

Manage Group Assets

=item *

Manage Asset Group Access

=back

Asset Group Access:

=over 4

=item *

Allow this user to access all asset groups

=back

Site Access:

=over 4

=item *

Allow this user to access all sites.

=back

If you automate this script, you should use an account that ONLY has these permissions. 
Avoid running the script as root or a nexpose administrator.

=head1 EXAMPLES

=over 4

=item Example 1: Everything in groups 1, 2, or 3

Lets say you have 3 groups, and you want a new group with everything in those groups.
You run GroupMaker, and see the group ids for those 3 groups are 1, 2, and 3. You
would create a group with the following rule:

=over 4

1 OR 2 OR 3

=back

Remember to use OR.  You want every device that is in group 1 or in 2 or in 3.  Don't
think "I want everything in 1 and 2 and 3."  That rule will give you only those assets
that appear in ALL three groups.

=item Example 2: Everything that is in both groups 1 and 2

If you want those items that appear in both groups 1 and 2, but not in only one or the
other, you would use AND:

=over 4

1 AND 2

=back

=item Example 3: All groups with "Team" in the name

In this example, let's assume you create dynamic asset groups for each team and have
a naming convention for these groups: each one begins with "Team -" 
and the team name.  EG, "Team - Network" for all the network team's assets. If you
want a group of all the assets that have been assigned to a "Devices" group, you could
run GroupMaker and create a group with the following rule:

=over 4

IMATCH(^devices)

=back

imatch will do a case-insensitive match for the regular expression ^devices.  The ^ is used
in regular expressions to indicate the start of a line.

=item Example 4: All assets that aren't assigned to a "Team" group

This example builds on the previous one. You need to find all the assets that haven't been
assigned to a team.  That is, you need all the assets that are not in a the group we created in 
Example 3.  For starters, you need a dynamic asset group that includes all assets.  Create that
in Nexpose.  (You might want to restrict it to assets that scanned in the last 30 or 90 days, 
so you aren't worrying about old systems.)  Lets call that group "All Assets", and the group from
Example 3 "All Teams."  When you run GroupMaker, it lists all your groups, and shows the group id's
(lets say "All Assets" = 10 and "All Teams" = 15).  To make a group that shows all assets that are not
in "All Teams", you would create a group with the following rule:

=over 4

10 AND NOT 15

=back

=back

=head1 CAVEATS

The script has not been tested on a system with only 1 existing asset group. It could fail
in such a situation.  (On the other hand, not sure how you would use it in such a case.)

The script assumes Nexpose enforces unique group names.  If two groups can have the same
name, this may fail.

=head1 COPYRIGHT AND LICENSE

Copyright 2013 misterpaul

This tool is free software; you may redistribute it and/or
modify it under the same terms as Perl.

=cut