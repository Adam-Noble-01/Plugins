/*******************************************************************************
 *
 * Thomas Thomassen
 * thomas[at]thomthom[dot]net
 *
 ******************************************************************************/


var tt_lib_installed = false;


function init_tabs()
{
  $(".tab:not(:first)").hide();
  $(".nav li:first").addClass("selected");
  //$(".tab:not(:nth-child(2))").hide();
  //$(".nav li:nth-child(2)").addClass("selected"); // DEBUG!
  $("a[href^='#']").on("click", function() {
    var $this = $(this);
    var id = $this.attr("href");
    $(".tab").hide(); // TODO: Only hide related tabs.
    $(".nav li").removeClass("selected");
    $(id).show();
    $tab = $(".nav a[href='" + id + "']");
    $tab.parent().addClass("selected");
    return false;
  })
}


function init_skp_links()
{
  var skp_links = $("a[href^='skp:']");
  skp_links.on("mouseenter", function() {
    $(".skp-menu").detach();
    var $this = $(this);
    setTimeout(function() {
      // Detect TT_Lib and prepend that to the list of RBZ files if it's
      // missing. The RBZ url list is ; separated list.
      var rbz_url = $this.data("rbz");
      if (!tt_lib_installed) {
        var tt_lib_url = "https://evilsoftwareempire.com/tt_lib2/download/latest";
        rbz_url = tt_lib_url + ";" + rbz_url;
      }
      var $menu = $("<div class='skp-menu'/>");
      var $link = $("<a>Install</a>");
      console.log(`rbz_url: ${rbz_url}`);
      $link.attr("href", "skp:installRBZ@" + rbz_url);
      $menu.append($link);
      $this.append($menu);
    }, 200);
  });
  skp_links.on("mouseleave ", function() {
    $(this).find(".skp-menu").detach();
  });
}


function init_update_dialog()
{
  $("#dialog-update").find("button").on("click", function() {
    $("#dialog-update").fadeOut('fast');
    Sketchup.callback("WelcomeWindow.dismiss_update");
    return false;
  })
}


function mark_tt_lib_installed()
{
  tt_lib_installed = true;
}


function update_available(version)
{
  var $messagebox = $('#dialog-update');
  $messagebox.find('p b').text(version);
  $messagebox.show();
}


$(document).ready(function() {
  init_tabs();
  init_skp_links();
  init_update_dialog();
  UI.redirect_links();
});
