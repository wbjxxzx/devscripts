package Local::Log;
use strict;
use Time::HiRes qw(time);
use POSIX qw(strftime);
use FileHandle;
use File::Spec;

sub new{
    my $class = shift;
    my %options = @_;
    my $self = {
            log_dir    => '.',
            log_name   => 'alpha.log',
            debug      => 1,
        };    
    foreach my $key(keys %$self){
        if(exists $options{$key}){
            $self->{$key} = $options{$key};
        }
    }
    my $logfile = File::Spec->catfile( @{$self}{qw(log_dir log_name)} );
    if(-e $logfile and -s _ > 20 * 1024 * 1024){
        chomp(my $lines = `perl -ne 'END{print \$.}' $logfile`);
        $lines = sprintf("%d",$lines/2);
        system "perl -ni -e 'print if(\$.>$lines)' $logfile";
    }
    $self->{fh} = FileHandle->new("$logfile",O_WRONLY | O_APPEND | O_CREAT) or die "connot open logfile:$!\n";
    $self->{fh}->autoflush(1);
    bless $self,$class;
}

sub _get_time{
    my ($sec,$msec) = split(/\./,time);
    $msec = $msec."0"x(5-length($msec));
    my $human_time = strftime("%Y-%m-%d %H:%M:%S",localtime($sec));
    "$human_time.$msec ";
}

sub write_file{
    my $self = shift;
    my $text = "@_";
    my $flag = ($self->{'debug'}) ? '[DEBUG] ' : '';
    $text .= "\n" unless $text =~ /(\012)$/;
    $self->{fh}->print(&_get_time,$flag,$text);
}

sub close_file{
    my $self = shift;
    $self->{fh}->close;
}

1;