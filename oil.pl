#!/usr/bin/perl

# Index netflow data from nfdump using Redis
#
# Given a flow like this ...
#
# Date first seen          Proto  Src IP Addr:Port     Dst IP Addr:Port
# 2018-10-19 10:14:50.000   UDP   10.0.0.1:36020   <-> 8.8.8.8:53
#
# ... we set a Redis key like this:
#
# 172.17.0.2:6379> get oil:8.8.8.8
# "/netflow/2018/10/19/router1/nfcapd.201810191010:10.0.0.1:8.8.8.8:36020:53:UDP"
#
# Now we have a very quick yes or no answer as to whether we've seen an IP in
# our environment.  If the answer is yes, we also know the most recent time we
# saw it.

use strict;

use File::Find;
use Getopt::Std;
use Parallel::ForkManager;
use Redis;

$| = 1;

our $NFDUMP    = "/usr/bin/nfdump";
our $REDIS     = Redis->new(server => '172.17.0.2:6379');
our $NAMESPACE = "oil";

my %opts;
getopts('m:rty', \%opts);

# Where does the netflow live?  The directory structure is assumed to be
# $flow_dir/YYYY/MM/DD/router-name/nfcapd.YYYYMMDDHHmm
my $flow_dir = "/netflow/by-date";

# Index today's netflow
if ($opts{t})
{
	my ($sec, $min, $hour, $mday, $mon, $year) = localtime(time());
	my $today = sprintf "%04d/%02d/%02d", $year + 1900, $mon + 1, $mday;
	$flow_dir = "$flow_dir/$today";
}
# Index yesterday's netflow
elsif ($opts{y})
{
	my ($sec, $min, $hour, $mday, $mon, $year) = localtime(time() - 86400);
	my $yesterday = sprintf "%04d/%02d/%02d", $year + 1900, $mon + 1, $mday;
	$flow_dir = "$flow_dir/$yesterday";
}
else 
{
	$flow_dir = shift;
}

if (!$flow_dir)
{
	die "Usage: $0 [-t | -y] [-m max forks] [flow dir]
	-t indexes today
	-y indexes yesterday";
}

# How many children should we fork?
my $maxprocs = $opts{m} || 1;

# Don't use this unless we're starting from scratch with an empty redis.  It
# runs the script in reverse chronological order and uses SETNX so the key is
# only set if it doesn't already exist.
our $REVERSE = $opts{r} || 0;

if (! -d $flow_dir && ! -l $flow_dir)
{
	die "$flow_dir: No such directory";
}

our @QUEUE;
find({wanted => \&enqueue, follow => 1}, $flow_dir);
my $pm = Parallel::ForkManager->new($maxprocs);
$pm->run_on_finish(
	sub {
		my $pid  = shift;
		my $code = shift;

		die if $code != 0;
	}
);

foreach my $file (sort { &cap_file_sort($a, $b) } @QUEUE)
{
	if ($REDIS->get("$NAMESPACE:$file") eq "done")
	{
		&log("$file is already done");
		next;
	}
	$pm->start() and next;

	&log("Indexing $file");
	my $start = time();
	my %ips = &extract_ips($file);
	if (!scalar(keys(%ips)))
	{
		warn "No ips in $file";
	}
	else
	{
		if ($REVERSE)
		{
			foreach my $ip (keys %ips)
			{
				# Need to fetch the old value and check the timestamp here
				$REDIS->setnx("$NAMESPACE:$ip", $ips{$ip});
			}
		}
		else
		{
			#$REDIS->set("$NAMESPACE:$ip", $ips{$ip});
			$REDIS->mset(map { ("$NAMESPACE:$_" => $ips{$_}) } keys(%ips));
		}
	}

	&log(scalar(keys(%ips)) . " ips in " . (time() - $start) . " seconds");
	$REDIS->set("$NAMESPACE:$file", "done");
	$pm->finish();
}
$pm->wait_all_children();

sub enqueue
{
	return if $File::Find::name !~ /\/([^\/]+)\/nfcapd.(\d\d\d\d)(\d\d)(\d\d)(\d\d\d\d)$/;
	push @QUEUE, $File::Find::name;
}

sub extract_ips
{
	my $filename = shift;
	my %ips;

	# We're passing $filename straight to the shell, so make
	# sure it doesn't have any shell metacharacters in it
	$filename =~ s/[^\/\.a-zA-Z0-9_\-]//g;
	my @nfdump = `$NFDUMP -r $filename -o "fmt:%sa %da %sp %dp %pr"`;
	foreach (@nfdump[1..$#nfdump - 4])
	{
		# Need to add a timestamp here
		my ($srcip, $dstip, $srcport, $dstport, $proto) = split;
		$ips{$srcip} = join(":", $filename, $srcip, $dstip, $srcport, $dstport, $proto);
		$ips{$dstip} = join(":", $filename, $srcip, $dstip, $srcport, $dstport, $proto);
	}
	return %ips;
}

# Sort nfcapd files by date.  E.g. when comparing ...
#
# /netflow/router1/nfcapd.201810191015 
#                ^        ^^^^^^^^^^^^
#
# ... to ...
#
# /netflow/router2/nfcapd.201810181010 
#                ^        ^^^^^^^^^^^^
#
# ... use 201810181010 and 201810191015 as the sorting keys to avoid putting a
# newer file first due to the router name being alphabetically lower.
sub cap_file_sort
{
	my ($a, $b) = @_;
	my ($date_a) = ($a =~ /\.(\d+)$/);
	my ($date_b) = ($b =~ /\.(\d+)$/);
	if ($REVERSE)
	{
		return $date_b <=> $date_a;
	}
	else
	{
		return $date_a <=> $date_b;
	}
}

sub log
{
	print "[$$] @_\n";
}
