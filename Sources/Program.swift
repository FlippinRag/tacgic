import Adwaita


@main
struct TragedyyyWorld: App {


    let id = "io.github.david_swift.HelloWorld"
    var app: AdwaitaApp!


    var scene: Scene {
        Window(id: "content") { window in
            // These are the views:
            // HeaderBar.empty()
            ContentView(app: app, window: window)
        }
        .defaultSize(width: 800, height: 600)
    }


}
