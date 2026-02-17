/*******************************************************************************
 *
 * Thomas Thomassen
 * thomas[at]thomthom[dot]net
 *
 ******************************************************************************/


function init_actions()
{
  $('#action-help').on('click', function() {
    Sketchup.callback("Window.help");
  });

  $('#action-close').on('click', function() {
    Sketchup.callback("Window.close");
  });
}


$(document).ready(function() {
  UI.disable_select();
  UI.disable_context_menu();
  init_actions();
});
