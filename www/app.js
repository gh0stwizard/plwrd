$( function() {
  var suffix = '/plwrd',
      ra = window.location.protocol + '//' + window.location.host + suffix + '?',
      nameRegex = /^[a-z]([0-9a-z_\-\.])+$/i;

  function sortByName( a, b ) {
    return ( a.name == b.name ) ? 0 : ( a.name < b.name ? -1 : 1 );
  }

  ko.bindingHandlers.showMe = {
    init: function ( element, valueAccessor ) {
      var shouldDisplay = valueAccessor();
      $( element ).toggle( shouldDisplay );
    },
    update: function ( element, valueAccessor ) {
      var shouldDisplay = valueAccessor();
      shouldDisplay ? $( element ).show() : $( element ).hide();
    }
  };

  function AppViewModel() {
    var self = this;

    // Data

    self.chosenListAppsData = ko.observableArray( [] );
    self.chosenAppData = ko.observable();
    self.logAppData = ko.observable();
    self.chosenAppDataEdit = ko.observable();
    self.errorMessage = ko.observable();
    self.commandStatus = ko.observable();
    self.onCreateApp = ko.observable();
    self.newAppName = ko.observable();
    self.newAppCmd = ko.observable();
    self.onAJAX = ko.observable();
    self.onWipeApps = ko.observable();

    self.errors = [
      'Connection error',
      'Bad request',
      'Not implemented',
      'Internal error',
      'Duplicate entry in a database',
      'Not found'
    ];


    // Behaviours

    self.showApps = function () {
      location.hash = '';
    }

    self.addNewApp = function () {
      location.hash = 'create';
    }

    self.addApp = function () {
      var name = self.newAppName(),
          cmd = self.newAppCmd(),
          valid = true;

      valid = valid && checkLength( name, 'Name', 2, 16 );
      valid = valid && checkRegexp( name, nameRegex, 'Name' );
      valid = valid && checkLength( cmd, 'Command', 1, 255 );

      valid && postJSON( suffix,
        {
          action: 'addApp',
          name: name,
          cmd: cmd
        },
        function ( data ) {
          if ( data.err ) {
            self.errorMessage( self.errors[ data.err ] );
          } else {
            self.newAppName( null );
            self.newAppCmd( null );
            self.onCreateApp( null );
            // get back to main page
            hasher.setHash( '' );
          }
        }
      );
    }

    self.runApp = function ( app ) {
      location.hash = 'run' + '/' + app.name;
    };

    self.showAppLog = function ( app ) {
      location.hash = 'log' + '/' + app.name;
    };

    self.editApp = function( app ) {
      location.hash = 'edit' + '/' + app.name;
    };

    self.wipeAppsAsk = function () {
      location.hash = 'wipe/apps';
    };

    self.wipeAppsBtn = function () {
      postJSON( suffix,
        { 
          action: 'wipeApps'
        },
        function ( data ) {
          if ( data.err ) {
            self.errorMessage( self.errors[ data.err ] );
          } else {
            // get back to main page
            hasher.setHash( '' );
          }
        }
      );
    };

    self.removeApp = function ( app )  {
      var name = app.name;

      postJSON( suffix,
        {
          action: 'delApp',
          name: name
        },
        function( data ) {
          if ( data.err ) {
            self.errorMessage( self.errors[ data.err ] );
          } else {
            // remove from a table
            self.chosenListAppsData.remove( app );
          }
        }
      );
    };

    self.updateApp = function ( app ) {
      postJSON( suffix,
        { 
          action: 'editApp',
          name: app.name,
          cmd: app.cmd
        },
        function ( data ) {
          // clear form
          self.chosenAppDataEdit( null );

          if ( data.err ) {
            self.errorMessage( self.errors[ data.err ] );
          } else {
            // get back to main page
            hasher.setHash( '' );
          }
        }
      );
    };

    self.createApp = function ( app ) {
      postJSON( suffix,
        { 
          action: 'addApp',
          name: app.name,
          cmd: app.cmd
        },
        function ( data ) {
          if ( data.err ) {
            self.errorMessage( self.errors[ data.err ] );
          } else {
            // get back to main page
            hasher.setHash( '' );
          }
        }
      );
    };


    // Formaters

    self.formattedLogs = ko.computed( function () {
      var logs = self.logAppData();

      if ( logs ) {
        // http://stackoverflow.com/questions/20964811/replace-amp-to-lt-to-and-gt-to-gt-in-javascript
        logs['stdout'] = $( '<div/>' ).html(logs['stdout'] ).text();
        logs['stderr'] = $( '<div/>' ).html(logs['stderr'] ).text();
      }

      return logs;
    } );

    self.formattedStatus = ko.computed( function() {
      var status = self.commandStatus();

      if ( status == null || status == undefined ) {
        return null;
      }

      return status ? 'Success' : 'Failed';
    } );


    // Helpers
    
    function cleanAll () {
      self.chosenListAppsData( [] );
      self.chosenAppData( null );
      self.logAppData( null );
      self.chosenAppDataEdit( null );
      self.commandStatus( null );
      self.onCreateApp( null );
      self.errorMessage( null );
      self.onWipeApps( null );
    }

    function getJSON ( url, cb ) {
      var numr = self.onAJAX() ? self.onAJAX() : 0;
      self.onAJAX( numr + 1 );

      $.ajax( {
        type: 'GET',
        url: url,
        dataType: 'json',
        cache: false,
        success: cb,
        error: function ( xhr, type, error ) {
          cleanAll();
          self.errorMessage( error );
        },
        complete: function () {
          var num = self.onAJAX() ? self.onAJAX() : 1;
          self.onAJAX( num - 1 );
        }
      } );
    }

    function postJSON( url, data, cb ) {
      var numr = self.onAJAX() ? self.onAJAX() : 0;
      self.onAJAX( numr + 1 );

      $.ajax( {
        type: 'POST',
        url: url,
        data: data,
        dataType: 'json',
        success: cb,
        error: function ( xhr, type, error ) {
          cleanAll();
          self.errorMessage( error );
        },
        complete: function () {
          var num = self.onAJAX() ? self.onAJAX() : 1;
          self.onAJAX( num - 1 );
        }
      } );
    }

    function makeRequest( action, name, cb ) {
      getJSON( ra + 'action=' + action + '&name=' + name, function( data ) {
        if ( data.err == null ) {
          cb( data );
        } else {
          self.errorMessage( self.errors[ data.err ] );
        }
      } );
    }

    function checkLength( o, n, min, max ) {
      if ( o == null || o == undefined ) {
        o = '';
      }

      if ( o.length > max || o.length < min ) {
        self.errorMessage( "Length of " + n + " must be between " 
                          + min + " and " + max );
        return false;
      } else {
        return true;
      }
    }

    function checkRegexp( o, regexp, n ) {
      if ( o == null || o == undefined ) {
        o = '';
      }

      if ( !( regexp.test( o ) ) ) {
        self.errorMessage( n + " contains invalid characters" );
        return false;
      } else {
        return true;
      }
    }


    // Router functions

    function listApps() {
      getJSON( ra + 'action=listApps', function( data ) {
        if ( data.err == null ) {
          self.chosenListAppsData( data );
          self.chosenListAppsData.sort( sortByName );
        } else {
          self.errorMessage( self.errors[ data.err ] );
        }
      } );
    }

    function getApp ( name, cb ) {
      makeRequest( 'getApp', name, cb );
    }

    function getAppLogs( name, cb ) {
      makeRequest( 'getLogs', name, cb );
    }

    function showAppLog ( name ) {
      getApp( name, self.chosenAppData );
      getAppLogs( name, self.logAppData );
    }

    function runApp ( name ) {
      getApp( name, self.chosenAppData );
      makeRequest( 'runApp', name, function ( data ) {
        self.commandStatus( data.result ? true : false ); // 1: ok, 0: an error
        getAppLogs( name, self.logAppData );
      } );
    }

    function createApp () {
      cleanAll();
      self.onCreateApp( true );
    }

    function wipe ( name ) {
      if ( name == 'apps' ) {
        cleanAll();
        self.onWipeApps( true );
      }
    }


    // Setup routers

    crossroads.addRoute( '', listApps );
    crossroads.addRoute( '/', listApps );
    crossroads.addRoute( 'create', createApp );
    var actionsRouter = crossroads.addRoute( '{action}/{name}' );

    actionsRouter.matched.add( function( action, name ) {
      self.chosenListAppsData( [] );
      self.logAppData( null );
      self.chosenAppDataEdit( null );

      switch ( action ) {
        case 'edit':
          self.chosenAppData( null );
          getApp( name, self.chosenAppDataEdit );
          break;
        case 'log':
          showAppLog( name );
          break;
        case 'run':
          runApp( name );
          break;
        case 'wipe':
          wipe( name );
          break;
        default:
          listApps();
      }
    } );


    // Setup hasher

    function parseHash( newHash, oldHash ) {
      // location has been switched to '/'
      if ( newHash == undefined || newHash === "" ) {
        self.chosenAppData( null );
        self.logAppData( null );
        self.chosenAppDataEdit( null );
        self.commandStatus( null );
        self.onCreateApp( null );
        self.errorMessage( null );
        self.onWipeApps( null);
      }

      crossroads.parse( newHash );
    }

    hasher.initialized.add( parseHash ); //parse initial hash
    hasher.changed.add( parseHash ); //parse hash changes
    hasher.init(); //start listening for history change
  }

  ko.applyBindings( new AppViewModel() );
} );