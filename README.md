# plwrd

plwrd - Perl Web Run Daemon, an HTTP application runner written in [Perl](http://www.perl.org).

# Why?

Just for fun. The possible usecases:

* Personal usage
* Internal usage inside a company

# Dependencies

This software requires next modules and libraries installed
via CPAN or other Perl package management system:

* EV
* AnyEvent
* Feersum
* HTTP::Body
* HTML::Entities
* JSON::XS
* File::Spec
* Getopt::Long
* UnQLite
* Sys::Syslog (optional)
* IO::FDPass
* Proc::FastSpawn
* AnyEvent::Fork
* AnyEvent::Fork::RPC
* AnyEvent::Fork::Pool

# Usage

The program is splitted in three major parts:

* starter: <code>main.pl</code>
* backend: <code>backend/feersum.pl</code>
* application: <code>app/feersum.pl</code>

To start the program type in console:

```
shell> perl src/main.pl
```

By default the server is listening on the address <code>127.0.0.1:28990</code>.
To run the listener on all interfaces and addresses you have to run 
the server as described below:

```
shell> perl src/main.pl --listen 0.0.0.0:28990
```

# Options

Use the option **--help** to see all available options:

```
shell> perl src/main.pl --help
Allowed options:
  --help [-h]              prints this information                         
  --version                prints program version                          

Web server options:
  --listen [-l] arg        IP:PORT for listener                            
                           - default: "127.0.0.1:28990"                    
  --background [-B]        run process in background                       
                           - default: run in foreground (disables logging) 
  --www-dir [-W] arg       www directory with index.html                   
                           - default is ../www                             
                           - useful when the program is running standalone 
Worker pool options:
  --max-proc arg           max number of worker processes                  
                           - default is 4                                  
  --max-load arg           max number of queued commands per worker        
                           - default is 1                                  
Security options:
  --home [-H] arg          working directory after fork                    
                           - default: root directory                       
  --chroot-dir [-C] arg    chroot directory                                
                           - works only when the program is started under root
                           - you have to copy apps and libs to this directory
  --euid arg               drop privileges to this user id                 
                           - default is nobody                             
Logging options:
  --debug                  be verbose                                      
  --verbose                be very verbose                                 
  --quiet [-q]             disables logging totally                        
  --enable-syslog          enable logging via syslog                       
  --syslog-facility arg    syslog's facility (default is LOG_DAEMON)       
  --logfile [-L] arg       path to log file (default is stdout)            

Miscellaneous options:
  --pidfile [-P] arg       path to pid file (default: none)                
  --backend [-b] arg       backend name (default: feersum)                 
  --app [-a] arg           application name (default: feersum)             

```

# Usage with nginx

The server is able to work together with [nginx](http://nginx.org).
The sample configuration file for nginx is placed in <code>conf/nginx/plwrd.conf</code>.

Using plwrd together with nginx is a good idea, because nginx is intended 
to cache static files.

# Development & Customization

The starter script <code>main.pl</code> was made to be independent
on a backend code, as possible at least.
To create your own backend you have to create a file in backend's directory.
For instance, for Twiggy, you may create file <code>src/backend/twiggy.pl</code>.
Then run the server in this way:

```
shell> perl src/main.pl --backend=twiggy
```

Note that the extention of the file was ommitted, as well as full path to
file.
