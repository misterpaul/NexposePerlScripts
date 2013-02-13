NAME
    GroupMaker - A script for creating groups of groups in Nexpose to create
    complex Asset Groups.

SYNOPSIS
    perl GroupMaker.pl --user=myname --host=nexpose.acme.com --port 3780

    perl GroupMaker.pl --rebuild

DESCRIPTION
    I wish Nexpose had the ability to create groups of groups. That is, you
    might need a group that was everything in Group A, Group B, but not in
    Group C. I am writing GroupMaker to address this need.

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
        that have been assigned to a "Team" group, you could run
        GroupMaker and create a group with the following rule:

            IMATCH(^team)

        imatch will do a case-insensitive match for the regular expression
        ^team. The ^ is used in regular expressions to indicate the
        start of a line.

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
