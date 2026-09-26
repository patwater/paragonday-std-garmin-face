// HorizonTimeApp.mc — App entry point

import Toybox.Lang;
import Toybox.Application;
import Toybox.WatchUi;
import Toybox.Position;

class HorizonTimeApp extends Application.AppBase {

    var _view as HorizonTimeView;

    function initialize() {
        AppBase.initialize();
        _view = new HorizonTimeView();
    }

    function getInitialView() as [ WatchUi.Views ] or [ WatchUi.Views, WatchUi.InputDelegates ] {
        return [ _view ];
    }

    // Watch faces cannot subscribe to GPS; HorizonTimeView reads the last known
    // position via Position.getInfo() when the day rolls over.
}
