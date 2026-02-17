function modifyAnchor(anchorID, url)
{
  var anchorelement = document.getElementById(anchorID);
  anchorelement.href= 'https://support.mindsightstudios.com/hc/en-us/articles/' + url + '?utm_source=plugin&utm_medium=instructor';
  anchorelement.target = "_blank";
}

function replaceText(elementID, platform, childIndex, text)
{
  var lineItem = document.getElementById(elementID);
  var os = navigator.appVersion.indexOf(platform) != -1? 1 : 0;
  var child = lineItem.children[childIndex];
  if (os == 1) {
    child.innerText = text;
  }
}

function replaceHtml(elementID, platform, childIndex, html)
{
  var lineItem = document.getElementById(elementID);
  var use_on_this_os = navigator.appVersion.indexOf(platform) != -1;
  var child = lineItem.children[childIndex];
  if (use_on_this_os) {
    child.innerHTML = html;
  }
}
