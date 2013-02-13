NAME
    GroupMaker - A script for creating groups of groups in Nexpose to create
    complex Asset Groups.

SYNOPSIS
    perl GroupMaker.pl

    perl GroupMaker.pl --user=myname --host=nexpose.acme.com --port 3780

    perl GroupMaker.pl --rebuild --user=groupmaker --pass=gr0upm^k3r
    --host=nexpose.acme.com --port 3780 --rotate=100

DESCRIPTION
    I wish Nexpose had the ability to create groups of groups. That is, you
    might need a group that was everything in Group A, Group B, but not in
    Group C. I wrote GroupMaker to address this need.

    When you create groups with a script (using the API), you can only
    create static groups. Therefore GroupMaker creates static groups. Once
    you create a group, its members stay the same until you change the
    group. To address this inability to create dynamic groups, GroupMaker
    has a "rebuild" mode, which will recreate all the groups you have saved.
    If you schedule GroupMaker to automatically run in rebuild mode (perhaps
    daily), your groups won't be truly dynamic, but they will at least be as
    current as the last time GroupMaker ran.

OPTIONS
    --rebuild
        Rebuilds all the groups that are set to Rebuild=On. It runs in a
        non-interactive manner. Therefore, you must also set user, pass,
        host, and port, either in the command line or by editing the script.
        Rebuilding a group defined by MATCH or IMATCH will re-run the match,
        so if a group was added or deleted, results may change. Also, there
        is no easy way to predict the correct order to rebuild matches (if
        one matched group depends on another matched group), so results
        could be off. Rebuilding a group defined by Group Ids will fail if
        one of the groups in the definition was deleted. The rebuilt group
        will have no devices.

        You may wish to run with --rebuild before running interactively to
        make sure your groups are up to date.

        GroupMaker analyzes the dependencies among groups of groups and
        rebuilds them in the proper order. One exception: it does not yet do
        this for groups defined with MATCH or IMATCH. I intend to fix that
        soon.

    --logfile=filename.log
        Sets the log file to filename.log. By default, the logfile is
        "groupmaker.log"

    --user=username
        Sets the username. You can edit the script to hard-code this if you
        wish.

    --pass=password
        Sets the password. You can edit the script to hard-code this if you
        wish.

    --host=hostname
        Sets the Nexpose host to connect to. You can edit the script to
        hard-code this if you wish.

    --port=port_number
        Sets the port used by Nexpose (most systems use 3780). You can edit
        the script to hard-code this if you wish.

    --rotate=log_size
        Rotates any log files larger than log_size (in MB).

        The script uses a very simplistic log rotation:

        (1) If a file exists with the same name as the logfile plus .old (eg
            groupmaker.log.old), delete it.

        (2) If a file exists with the name of the logfile, rename it, adding
            .old to the end.

        If you need anything more sophisticated, write it yourself, or use
        an external tool to do it.

    --man
        Displays the full documentation (man page)

    --help
        Displays a shortened documentation

CREATING NEW GROUPS.
    When you run GroupMaker interactively, you are guided through the
    process of creating a new group. First, you are presented with a list of
    all your current groups and their group ids. It will look something like
    this:

         **************************************************************************
         * GroupMaker - please run GroupMaker.pl --man for complete info on use. *
         **************************************************************************

           Group Id     Group Name
           --------     --------------------------------------------------
            ( 3 )       A Group I Created
            ( 1 )       ALL ASSETS
            ( 2 )       Test Group

         Define your group of groups by using the Group Ids above and logic
         statements using AND, OR, NOT, and parentheses. Or, use MATCH()
         or IMATCH() to select all the groups that match a regular expression.
         (NOTE: MATCH() and IMATCH() can not be used with group numbers or
         logic statements.)  When using MATCH & IMATCH, be sure
         to escape any special characters (pretty much anything that isn't
         a number or letter) with a backslash  if they are a part of the
         search string.

         Keep it simple. You can build more complex groups by making groups of
         these groups.

         Define your group of groups here:

    At this point, you create a rule to define what your group will contain.

    For example:

        1 OR 2 OR 3
            This group will have everything from 1, 2, & 3

        (1 OR 2 OR 3) AND NOT 4
            This group will have everything from 1, 2, & 3, as long as it is
            not in 4

        1 AND 2
            This group will have everything that appears in both 1 & 2

        MATCH(^teams)
            This group will have everything that is in any group whose name
            begins with "teams"

        IMATCH(^teams)
            Same as above, but case-independent.

    Next, you are asked to provide a name for the group:

         Now, provide the details about the group we're going to create.

         Group Name:

    Then, you are asked to enter a description for the group (this is
    optional).

         Description:

    Finally, you are asked whether you will want this group rebuilt when you
    run GroupMaker with the --rebuild option.

         Do you want to rebuild this group whenever GroupMaker is run with --rebuild?
         Please enter Yes, No, or Quit (y,n,q):

    If all goes well, you'll see a message indicating that your group was
    built, and you're done!

         Creating group My Sample Group...
         Group created successfully

LOGGING
    All results are logged to groupmaker.log unless overridden by --logfile.

AUTHENTICATION & AUTHORIZATION
    NOTE: This script appears to need Nexpose full admin rights in order to
    rebuild groups. I believe this is a bug in Nexpose and will report it.
    So, until this is resolved, it looks like you need to disregard the info
    below and run as an administrator, at least for rebuilding groups

    The account used to run this script SHOULD only need the following
    permissions in Nexpose:

    Roles - set to custom:

    *   Manage Dynamic Asset Groups (this might not be necessary, but it
        ensures the user can access all sites)

    *   Manage Static Asset Groups

    *   View Group Asset Data

    *   Manage Group Assets

    *   Manage Asset Group Access

    Asset Group Access:

    *   Allow this user to access all asset groups

    Site Access:

    *   Allow this user to access all sites.

    If you automate this script, you should use an account that ONLY has
    these permissions. Avoid running the script as root or a nexpose
    administrator.

EXAMPLES
    Example 1: Everything in groups 1, 2, or 3
        Lets say you have 3 groups, and you want a new group with everything
        in those groups. You run GroupMaker, and see the group ids for those
        3 groups are 1, 2, and 3. You would create a group with the
        following rule:

            1 OR 2 OR 3

        Remember to use OR. You want every device that is in group 1 or in 2
        or in 3. Don't think "I want everything in 1 and 2 and 3." That rule
        will give you only those assets that appear in ALL three groups.

    Example 2: Everything that is in both groups 1 and 2
        If you want those items that appear in both groups 1 and 2, but not
        in only one or the other, you would use AND:

            1 AND 2

    Example 3: All groups with "Team" in the name
        In this example, let's assume you create dynamic asset groups for
        each team and have a naming convention for these groups: each one
        begins with "Team" and the team name. EG, "Team - Network" for all
        the network team's assets. If you want a group of all the assets
        that have been assigned to a "Team" group, you could run GroupMaker
        and create a group with the following rule:

            IMATCH(^team)

        imatch will do a case-insensitive match for the regular expression
        ^team. The ^ is used in regular expressions to indicate the start of
        a line.

    Example 4: All assets that aren't assigned to a "Team" group
        This example builds on the previous one. You need to find all the
        assets that haven't been assigned to a team. That is, you need all
        the assets that are not in a the group we created in Example 3. For
        starters, you need a dynamic asset group that includes all assets.
        Create that in Nexpose. (You might want to restrict it to assets
        that scanned in the last 30 or 90 days, so you aren't worrying about
        old systems.) Lets call that group "All Assets", and the group from
        Example 3 "All Teams." When you run GroupMaker, it lists all your
        groups, and shows the group id's (lets say "All Assets" = 10 and
        "All Teams" = 15). To make a group that shows all assets that are
        not in "All Teams", you would create a group with the following
        rule:

            10 AND NOT 15

INTERNALS
    GroupMaker adds its own information to the group's description. If you
    edit the group within Nexpose, you will see that the description looks
    something like this:

        The description I entered (This group was created by the GroupMaker
        script. Rule='imatch(^team)'. Rebuild=On. First created: Tue Feb 12
        16:02:13 2013. Rebuilt: Tue Feb 12 21:08:24 2013.)

    You can edit the description before and after the parenthesis however
    you want. Just don't touch what is between the parenthesis, unless you
    want to mess up your group definitions!

RECOMMENDATIONS
    *   Keep your logic simple. For complex groups, build simple groups,
        then build groups of those groups. That way, you can check the
        intermediate groups to see that they are what you expect.

    *   Look out for groups with 0 members. There may have been an error
        when rebuilding the group.

    *   Rebuilding

        - Set up a schedule (eg cron) to run --rebuild nightly or a few
        times a day.
        - Always run --rotate when you run --rebuild
        - Monitor your logs Search for "ERROR". Better yet, ship the logs to
        a monitoring tool that will alert if it sees ERROR.

CAVEATS
    The script has not been tested on a system with only 1 existing asset
    group. It could fail in such a situation. (On the other hand, not sure
    how you would use it in such a case.)

    The script assumes Nexpose enforces unique group names. If two groups
    can have the same name, this may fail.

COPYRIGHT AND LICENSE
    Copyright 2013 misterpaul

    This tool is free software; you may redistribute it and/or modify it
    under the same terms as Perl.
