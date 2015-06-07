$( function() {
/*
  var $pathname = window.location.pathname;
  var $addr = window.location.protocol + '//' + window.location.host;
  var $action_name = $( "#postForm" ).attr( "action" );
  var url = $addr + $action_name + "?json=" + $pathname.substring( 1 );
*/

  /* Initialize tabs */

  $( "#tabs" ).tabs( { 
    beforeLoad: function( event, ui ) {
      ui.jqXHR.fail( function() {
        ui.panel.html( "Could not load page" );
      } );
    }
  } );

} ); // document.ready
