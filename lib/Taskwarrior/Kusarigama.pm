package Taskwarrior::Kusarigama;
# ABSTRACT: plugin system for the Taskwarrior task manager

=head1 SYNOPSIS

    $ task-kusarigama add GitCommit Command::ButBefore Command::AndAfter

    $ task-kusarigama install

    # enjoy!

=head1 DESCRIPTION

This module provides a plugin-based way to run hooks and custom
commands for the 
cli-based task manager L<Taskwarrior|http://taskwarrior.org/>.

=head2 Configuring Taskwarrior to use Taskwarrior::Kusarigama

=head3 Setting up the hooks

Taskwarrior's main method of customization is via hooks
that are executed when the command is run, when it exits, and when
tasks are modified or added. (see L<https://taskwarrior.org/docs/hooks.html>
for the official documentation) C<Taskwarrior::Kusarigama> leverages this
hook system to allow the creation of custom behaviors and commands.

First, you need to install hook scripts that will invoke C<Taskwarrior::Kusarigama>
when C<task> is running. You can do that by either using the helper C<task-kusarigama>:

    $ task-kusarigama install

Or dropping manually hook scripts in the F<~/.task/hooks> directory. The scripts
should look like

    #!/usr/bin/env perl

    # script '~/.task/hooks/on-launch-kusarigama.pl'

    use Taskwarrior::Kusarigama;

    Taskwarrior::Kusarigama->new( raw_args => \@ARGV )
        ->run_event( 'launch' ); # change with 'add', 'modify', 'exit' 
                                 # for the different scripts

=head3 Setting which plugins to use

Then you need to tell the system with plugins to use, 
either via C<task-kusarigama>

    $ task-kusarigama add Command::AndAfter

or directly via the Taskwarrior config command

    $ task config  kusarigama.plugins  Command::AndAfter

=head3 Configure the plugins

The last step is to configure the different plugins. Read their 
documentation to do it manually or, again, use C<task-kusarigama>.

    $ task-kusarigama install

=head2 Writing plugins

The inner workings of the plugin system are fairly simple.

The list of plugins we want to be active lives in the taskwarrior
configuration under the key <kusarigama.plugins>. E.g.,

    kusarigama.plugins=Renew,Command::ButBefore,Command::AndAfter,+FishCurrent

Plugin namess prefixed with a plus sign are left left alone (minus the '+'),
while the other ones get C<Taskwarrior::Kusarigama::Plugin::> prefixed to
them.

The Taskwarrior::Kusarigama system itself is invoked via the 
scripts put in F<~/.task/hooks> by C<task-kusarigama>. The scripts
detect in which stage they are called (launch, exit, add or modified),
and execute all plugins that consume the associated role (e.g., 
L<Taskwarrior::Kusarigama::Hook::OnLaunch>), in the order they have been 
configured. 

For example, this plugin will runs on a four hook stages:

    package Taskwarrior::Kusarigama::Plugin::PrintStage;

    use 5.10.0;

    use strict;
    use warnings;

    use Moo;

    extends 'Taskwarrior::Kusarigama::Plugin';

    with 'Taskwarrior::Kusarigama::Hook::OnLaunch',
         'Taskwarrior::Kusarigama::Hook::OnAdd',
         'Taskwarrior::Kusarigama::Hook::OnModify',
         'Taskwarrior::Kusarigama::Hook::OnExit';

    sub on_launch { say "launch stage: ", __PACKAGE__; }
    sub on_add    { say "add stage: ",    __PACKAGE__; }
    sub on_modify { say "modify stage: ", __PACKAGE__; }
    sub on_exit   { say "exit stage: ",   __PACKAGE__; }

    1;

=head3 The Fifth Column: Taskwarrior::Kusarigama::Hook::OnCommand

Kusarigama defines a fifth hook role,
L<Taskwarrior::Kusarigama::Hook::OnCommand>, to help creating
custom commands. This role does two things: when
C<task-kusarigama install> is run, it creates a dummy report
such that Taskwarrior will accept C<task my_custom_command> as a 
valid invocation, and then it runs as part of the C<launch>
stage and will run the plugin code if the associated command was used.


=head3 Adding custom fields to tasks

Taskwarrior allows the creation of I<User-Defined Attributes> (UDAs). Plugins
can implement a C<custom_uda> attribute that holds a hashref of 
new UDAs and their description. Those UDAs will then be fed to Taskwarrior's
config via C<task-kusarigama install>, and will thereafter be available like
any other task field.

For example, L<Taskwarrior::Kusarigama::Plugin::Renew> uses UDAs
to identify tasks that should create a new, follow-up instance
of themselves upon completion:

    package Taskwarrior::Kusarigama::Plugin::Renew;

    use strict;
    use warnings;

    use Clone 'clone';
    use List::AllUtils qw/ any /;

    use Moo;
    use MooseX::MungeHas;

    extends 'Taskwarrior::Kusarigama::Hook';

    with 'Taskwarrior::Kusarigama::Hook::OnExit';

    use experimental 'postderef';

    has custom_uda => sub{ +{
        renew => 'creates a follow-up task upon closing',
        rdue  => 'next task due date',
        rwait => 'next task wait period',
    } };

    sub on_exit {
        my( $self, @tasks ) = @_;

        return unless $self->command eq 'done';

        my $renewed;

        for my $task ( @tasks ) {
            next unless any { $task->{$_} } qw/ renew rdue rwait /;
            $renewed = 1;

            my $new = clone($task);

            delete $new->@{qw/ end modified entry status uuid /};

            my $due = $new->{rdue};
            $new->{due} = $self->calc($due) if $due;

            my $wait = $new->{rwait};
            $wait =~ s/due/$due/;
            $new->{wait} = $self->calc($wait) if $wait;

            $new->{status} = $wait ? 'waiting' : 'pending';

            $self->import_task($new);
        }

        $self .= 'created follow-up tasks' if $renewed;
    }

    1;

=head3 Aborting the pipeline

Any plugin can abort the taskwarrior process by simply C<die>ing.

    sub on_add {
        my( $self, $task ) = @_;

        die "need jira ticket for work tasks"
            if $task->{project} eq 'work' and not $task->{jira};
    }

=head1 SEE ALSO

=over

=item L<http://techblog.babyl.ca/entry/taskwarrior> 

the original blog entry

=back

=cut

# TODO document the kusarigama.dir key
1;
