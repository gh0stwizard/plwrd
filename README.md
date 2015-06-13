# plwrd #

plwrd - Perl Web Run Daemon, an HTTP application runner written in [Perl](http://www.perl.org).

# Why? #

Just for fun. The possible usecases:

* Personal usage
* Internal usage inside a company

# Dependencies #

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

# Usage #

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
shell> PERL5LIB=src/modules perl src/main.pl --listen 0.0.0.0:28990
```

The <code>PERL5LIB</code> environment variable is required and 
says Perl where is the additional modules are placed. So, 
you have not to copy (install) modules by a hand to start 
a program.

# Options #

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

# Usage with nginx #

The server is able to work together with [nginx](http://nginx.org).
The sample configuration file for nginx is placed in <code>conf/nginx/plwrd.conf</code>.

Using plwrd together with nginx is a good idea, because nginx is intended 
to cache static files.

# Development & Customization #

The starter script <code>main.pl</code> was made to be independent
on a backend code, as possible at least.
To create your own backend you have to create a file in backend's directory.
For instance, for Twiggy, you may create file <code>src/backend/twiggy.pl</code>.
Then run the server in this way:

```
shell> PERL5LIB=src/modules perl src/main.pl --backend=twiggy
```

Note that the extention of the file was ommitted, as well as full path to
file.

In the same way you may create your own application file, e.g. 
<code>src/app/mojo.pl</code>.


# API #

## Introduction ##

A server side works together with a frontend side via AJaX requests.
Requests are splitted into two groups: GET and POST. The GET requests
are using mostly for retrieving a data from the server. Meantime the
POST requests are using for storing a data on the server.

All types of requests are using JSON encoding.

## How to catch an error ##

When an error occurs on the server side, the server will response with
a hash object. In that case _all_ types of requests returns 
the hash object with only one key <code>err</code>.
The value for the key is a number with an error code.

Currently, the server is using next error codes:

* <code>0</code> - Connection error
* <code>1</code> - Bad request
* <code>2</code> - Not implemented
* <code>3</code> - Internal error
* <code>4</code> - Duplicate entry in a database
* <code>5</code> - Not found


## GET requests ##

Currently, all GET requests are using the next semantic:

```
?action=ACTION&name=NAME
```

where is ACTION means a command to execute on the server,
and NAME is additional argument. Some actions runs without
the NAME parameter.

A list of actions and their descriptions:

* listApp
* getApp
* getLogs

### listApp ###

* Parameters: none
* Returns: an array of hashes

Each hash contains <code>name</code>, <code>cmd</code> 
and <code>user</code> attributes.

If an error occurs a common error hash with the key <code>err</code>
is returned. This note is also applied to _all_ requests.

### getApp ###

* Parameters: name
* Returns: a hash object

On success the hash object contains <code>name</code>, <code>cmd</code> 
and <code>user</code> attributes.

### getLogs ###

* Parameters: name
* Returns: a hash object

On success the hash object contains:

* <code>name</code> - the name of requested app
* <code>stdout</code> - a text of stdout output
* <code>stderr</code> - a text of stderr output

Otherwise, returns a hash with an <code>err</code> attribute.


## POST requests ##

The POST requests are working like the GET requests. They are
also using parameters ACTION and NAME like shows above. In an
addition POST requests may have other parameters, all of them
are described below.

A list of actions and their descriptions:

* addApp
* delApp
* editApp
* wipeApps

### addApp ###

* Parameters: name, cmd, user
* Returns: a hash object

Stores an application record to a database on the server side.

On success returns a hash object with a <code>name</code> attribute.

### delApp ###

* Parameters: name
* Returns: a hash object

Removes a record from a database.

On success returns a hash object with a <code>name</code> attribute.

### editApp ###

* Parameters: name, cmd, user
* Returns: a hash object

Updates an application record with the name <code>name</code>.

On success returns a hash object with a <code>name</code> attribute.

### wipeApps ###

* Parameters: none
* Returns: a hash object

Deletes all application records from a datase.

On success returns a hash object with a <code>wiped</code> attribute.
The value is a number of deleted records.
