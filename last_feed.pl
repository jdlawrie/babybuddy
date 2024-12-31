#!/usr/local/bin/perl

# Cronjob to send NTFY notification if the last feeding was 3 hours ago.
# Will also send an SMS because I find ntfy to be unreliable at night even with battery saving turned off.

use strict;
use warnings;

use LWP::UserAgent;
use JSON qw(decode_json);
use Time::Piece;      # For parsing date/time
use Time::Seconds;    # For constant SECONDS

my $api_url = 'https://URL_OF_BABY_BUDDY/api/feedings/?limit=1';
my $token   = 'ENTER_API_TOKEN_HERE';

my $alert_file   = "/tmp/last_alert_id";
my $feeding_file = "/tmp/last_feeding_id";

my $last_alert   = "";
my $last_feeding = "";

my $baby_name  = "Name"; # This is only setup for one baby. 
my $ntfy   = "https://ntfy.url.here/${baby_name}_feed";
my $sms_no = "+1234567890"

if (-e $alert_file) {
    open my $fh, '<', $alert_file or die "Cannot open $alert_file: $!";
    chomp($last_alert = <$fh>);
    close $fh;
}

if (-e $feeding_file) {
    open my $fh, '<', $feeding_file or die "Cannot open $feeding_file: $!";
    chomp($last_feeding = <$fh>);
    close $fh;
}

my $ua = LWP::UserAgent->new();
my $response = $ua->get($api_url, 'Authorization' => "Token $token");
die "HTTP GET error: ", $response->status_line
    unless $response->is_success;

my $data = decode_json($response->decoded_content);
my $start_time_iso = $data->{results}[0]{start};
my $last_feed_start = $start_time_iso; # Copying for the alert
# This is a bit hacky, I didn't want to deal with timezones
$last_feed_start =~ s/T/ /; $last_feed_start =~ s/\+.*//;
my $id = $data->{results}[0]{id};
my $amount  = $data->{results}[0]{amount};
my $details = "$data->{results}[0]{type} ($data->{results}[0]{method})";
if ($amount) { $details = "${amount}ml $details"; }

if ($id eq $last_alert) {
    exit 0;
}

if ($id ne $last_feeding) {
    alert("$baby_name was just fed\n$details\n$last_feed_start", "low");
    open my $fh, '>', $feeding_file or die "Cannot write $feeding_file: $!";
    print $fh $id;
    close $fh;
}

if ($id ne $last_alert) {
    $start_time_iso =~ s/([+-]\d{2}):(\d{2})$/$1$2/u;
    $start_time_iso =~ s/Z$/+0000/;
    my $start_time = Time::Piece->strptime($start_time_iso, '%Y-%m-%dT%H:%M:%S%z');
    my $now = localtime;
    my $difference = $now - $start_time;
    # Check if difference is greater than 3 hours
    if ($difference > 3 * ONE_HOUR) {
	      alert("$baby_name needs feeding ffs\n\nLast feed was at $last_feed_start)", "urgent");
        open my $fh, '>', $alert_file or die "Cannot write $alert_file: $!";
        print $fh $id;
        close $fh;
    }
}

sub alert {
   my $content = shift;
   my $priority = shift;
   my $response = $ua->post($ntfy, 'Content-Type' => 'text/plain', 'Priority' => $priority, Content => $content);
   if ($priority eq "urgent") {
	   `/usr/local/bin/aws sns publish --message "Feed me ffs" --phone-number $sms_no --region=eu-central-1  --message-attributes "AWS.SNS.SMS.SenderID={DataType=String,StringValue=BabyBuddy}"`;
   }
}
