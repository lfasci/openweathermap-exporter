This is yeta another an OpenWeatherMap exporter for Prometheus, it exposes weather metrics.

The config file `/etc/sensors/openweathermap.yml` would look like:

````
base_url: "http://api.openweathermap.org/data/2.5/weather"
http_port: "12345"
api_key: <yourkey>
units: metric
lang: it
cities:
  - Pisa
  - Roma
  - Catania

````

http_port is the tcp port where the server will listen

## Install

This script needs perl modules that you can install from cpan

cpanm install HTTP::Server::Simple::CGI
cpanm install Config::YAML
cpanm install CGI
cpanm install Data::Dumper
cpanm install JSON
cpanm install LWP::UserAgent::Determined
cpanm install URI::Escape
cpanm install Text::Unidecode

Copy the script in /usr/local/sbin/
Make it executable
chmod +x /usr/local/sbin/openweathermap_exporter.pl

## Run

/usr/local/sbin/openweathermap_exporter.pl > /dev/null 2>&1

To stop, kill its PID
