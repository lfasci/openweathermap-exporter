#!/usr/bin/perl


package openweatherPrometheusExporter;
use HTTP::Server::Simple::CGI;
use base qw(HTTP::Server::Simple::CGI);
use Config::YAML;
use CGI;
use Data::Dumper;
use JSON;
use LWP::UserAgent::Determined;
use URI::Escape;
use Fcntl ':flock';
use Text::Unidecode;
use strict;
use Geo::Hash;
use warnings;

open my $self, '<', $0 or die "Couldn't open self: $!";
flock $self, LOCK_EX | LOCK_NB or die "This script is already running";

my $configFile = $ARGV[0] || "/etc/sensors/openweathermap.yml";
my $config = Config::YAML->new( config => $configFile);
my $baseUrl = $config->{base_url};
my $httpPort = $config->{http_port};

my $pid = openweatherPrometheusExporter->new($httpPort)->background();

#################################################################################################

sub getSensors() {
	my $config = shift;

	my $api_key = $config->{api_key};
	my $units = $config->{units};
	my $lang = $config->{lang};

	my $ua = LWP::UserAgent::Determined->new;
	$ua->timing("1,2,5");

	my $output = "# OpenWeather prometheus exporter\n";

	my @urls;

	if ($config->{cities}) {
			foreach my $city (@{$config->{cities}}) {
				push @urls, $baseUrl."?q=". uri_escape($city) ."&appid=$api_key"."&units=$units"."&lang=$lang";
			}
	}

	if ($config->{latlons}) {
			foreach my $latlon (@{$config->{latlons}}) {
					my $lat = $latlon->[0];
					my $lon = $latlon->[1];
					push @urls, $baseUrl."?lat=$lat&lon=$lon&appid=$api_key"."&units=$units"."&lang=$lang";
			}
	}

	if ($config->{zips}) {
			foreach my $zip (@{$config->{zips}}) {
					push @urls, $baseUrl."?zip=$zip,us&appid=$api_key"."&units=$units"."&lang=$lang";
			}
	}

	foreach my $url (@urls) {
			my $api_key=$config->{api_key};
			my $json = $ua->get($url);
			#TODO count up errors instead of dying once this becomes a daemon
			die "Could not get $url: $!" unless $json->is_success;
			# print Dumper($json->content);
			my $decoded_json = decode_json( $json->content );
			my $location = &cleanString($decoded_json->{name});

			my $gh = Geo::Hash->new;
			my $latitude = $decoded_json->{coord}{lat};
			my $longitude = $decoded_json->{coord}{lon};
			my $geohash = $gh->encode($latitude, $longitude);

			$output .= "# OpenWeather data for $location\n";
			$output .= "info{location=\"$location\", id=\"$decoded_json->{id}\", country=\"$decoded_json->{sys}{country}\", geohash=\"$geohash\"} 1\n";

			$output .= "# Weather in $location\n";
			$output .= "id{location=\"$location\", description=\"$decoded_json->{weather}[0]{description}\"} $decoded_json->{weather}[0]{id}\n";

			$output .= "# Temperatures in $location\n";
			$output .= "temperature{location=\"$location\",type=\"current\", geohash=\"$geohash\"} $decoded_json->{main}{temp}\n";
			$output .= "temperature{location=\"$location\",type=\"max\", geohash=\"$geohash\"} $decoded_json->{main}{temp_max}\n";
			$output .= "temperature{location=\"$location\",type=\"min\", geohash=\"$geohash\"} $decoded_json->{main}{temp_min}\n";

			#Should be converted to timestamp 
			#$output .= "measurement_epoch{location=\"$location\"} $decoded_json->{dt}\n";

			$output .= "# Wind in $location\n";
			# This is not always returned
			my $windDirection = "";
			if (defined $decoded_json->{wind}{deg}) {
				$windDirection = $decoded_json->{wind}{deg};
			} 
			$output .= "wind_speed{location=\"$location\" winddirection=\"$windDirection\", geohash=\"$geohash\"} $decoded_json->{wind}{speed}\n";

			# TODO I fear there might be multiple arrays in there, sometimes
			# $output .= "id{location=\"$location\"} $decoded_json->{weather}[0]{id}\n";

			# $output .= "location_coordinates{location=\"$location\",dimension=\"latitude\"} $decoded_json->{coord}{lat}\n";
			# $output .= "location_coordinates{location=\"$location\",dimension=\"longitude\"} $decoded_json->{coord}{lon}\n";

			$output .= "# Humidity in $location\n";
			$output .= "humidity_percent{location=\"$location\", geohash=\"$geohash\"} $decoded_json->{main}{humidity}\n";

			$output .= "# Clouds in $location\n";
			$output .= "clouds_percent{location=\"$location\", geohash=\"$geohash\"} $decoded_json->{clouds}{all}\n";

			$output .= "# Sun in $location\n";
			$output .= "sun_epoch{location=\"$location\",change=\"sunrise\", geohash=\"$geohash\"} $decoded_json->{sys}{sunrise}\n";
			$output .= "sun_epoch{location=\"$location\",change=\"sunset\", geohash=\"$geohash\"} $decoded_json->{sys}{sunset}\n";

			$output .= "# Pressure in $location\n";
			$output .= "pressure_hectopascal{location=\"$location\",level=\"current\", geohash=\"$geohash\"} $decoded_json->{main}{pressure}\n";
			# $output .= "pressure_hectopascal{location=\"$location\",level=\"ground\"} $decoded_json->{main}{grnd_level}\n" if defined $decoded_json->{main}{grnd_level};
			# $output .= "pressure_hectopascal{location=\"$location\",level=\"sea\"} $decoded_json->{main}{sea_level}\n" if defined $decoded_json->{main}{sea_level};
	}

	my $cgi = CGI->new();
	my $nl = "\x0d\x0a";
	print "HTTP/1.0 200 OK$nl";
	print $cgi->header("text/plain"),$output;
}

#Prometheus only accepts ASCII so I have to clean strings
sub cleanString {
	my $str = shift;
	$str = unidecode($str);
	$str =~ s/[^a-zA-Z0-9,\s]/ /g;
	$str =~ s/\s+/ /g;
	if(substr ($str, -1) eq ' '){
		chop $str;
	}
	return $str;
}

sub handle_request {
	my $self = shift;
	my $cgi = shift;
	
    my $path = $cgi -> path_info;

    if ($path eq '/metrics') {
		&getSensors($config);
	}	
}
