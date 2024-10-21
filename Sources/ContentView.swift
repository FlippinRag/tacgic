@preconcurrency import Adwaita
import Foundation
import FoundationNetworking

struct ContentView: View {
    @State("selection") private var selection: Page = .games
    @State private var sidebarVisible = true
    @State private var about = false
    @State private var width = 650
    @State private var height = 550
    @State private var maximized = false

    var app: AdwaitaApp!
    var window: AdwaitaWindow

    var view: Body {
        OverlaySplitView(visible: $sidebarVisible) {
            ScrollView {
                List(Page.allCases, selection: $selection) { element in
                    Text(element.title)
                        .halign(.start)
                        .padding()
                }
                .sidebarStyle()
            }
            .topToolbar {
                HeaderBar.end {
                    menu
                }
                .headerBarTitle {
                    WindowTitle(subtitle: "", title: "Tragic World")
                }
            }
        } content: {
            selection.view()
                .topToolbar {
                    HeaderBar {
                        Toggle(icon: .default(icon: .sidebarShow), isOn: $sidebarVisible)
                            .tooltip("Toggle Sidebar")
                    } end: {
                        if sidebarVisible {
                            Text("").transition(.crossfade)
                        } else {
                            menu.transition(.crossfade)
                        }
                    }
                    .headerBarTitle {
                        if sidebarVisible {
                            Text("")
                                .transition(.crossfade)
                        } else {
                            WindowTitle(subtitle: "Demo", title: selection.title)
                                .transition(.crossfade)
                        }
                    }
                }
        }
        .sidebarWidthFraction(0.2)
    }

    

    var menu: AnyView {
        Menu(icon: .default(icon: .openMenu)) {
            MenuButton("New Window", window: false) {
                app.addWindow("main")
            }
            .keyboardShortcut("n".ctrl())
            MenuButton("Close Window") {
                window.close()
            }
            .keyboardShortcut("w".ctrl())
            MenuSection {
                MenuButton("About") { about = true }
                MenuButton("Quit", window: false) { app.quit() }
                    .keyboardShortcut("q".ctrl())
            }
        }
        .primary()
        .tooltip("Main Menu")
    }
}

struct WebView: View {
    var view: Body {
        Text("This would be the webview in linuxxxx")
            .padding()

    }
}

struct GamesView: View {
    @State private var games: [GameData] = []
    @State private var isLoading = true
    @State private var selectedGame: String = ""  
    private let legendary: Legendable = Nix()

    var view: Body {
        ScrollView {
            if isLoading {
                Spinner()
            } else if games.isEmpty {
                Text("No games found")
                    .valign(.center)
                    .halign(.center)
            } else {
                FlowBox(games, selection: $selectedGame) { game in
                    GameCard(game: game)
                }
                .padding()

            }
        }
        .onAppear {
            fetchGames()
        }
    }

    private func fetchGames() {
        Task.detached(priority: .userInitiated) { [legendary] in
            let receivedGames = await legendary.loadAllGameData() ?? []
            Idle {
                self.games = receivedGames
                self.isLoading = false
            }
        }
    }
}

struct GameCard: View {
    let game: GameData

    var view: Body {
        VStack {
            AsyncImage(url: game.keyImage?.url ?? "", size: 150)
            Label(game.appTitle ?? "Unknown")
        }
        .padding()
        .style("game-card")
        .css{
             """
            .game-card {
                border: 1px solid #ccc;
                border-radius: 5px;
                padding: 5px;
                margin: 5px;
            }
            """
        }
    }
}

struct AsyncImage: View {
    var url: String
    var size: Int = 400

    @State private var data: Data?
    @State private var isLoading = true
    @State private var loadError = false

    var view: Body {
        VStack {
            if isLoading {
                Spinner()
            } else if loadError {
                Picture()
                    .data(nil)
            } else {
                Picture()
                    .data(data)
            }
        }
        .frame(minWidth: size, minHeight: size)
        .onAppear {
            loadImage()
        }
    }

    private func loadImage() {
        guard let url = URL(string: url) else {
            loadError = true
            isLoading = false
            return
        }

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                Idle {
                    self.data = data
                    self.isLoading = false
                }
            } catch {
                print("Error loading image: \(error)")
                Idle {
                    self.loadError = true
                    self.isLoading = false
                }
            }
        }
    }
}



enum Page: CaseIterable, Identifiable, Decodable, Encodable {
    case games
    case web

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .games:
            return "Games"
        case .web:
            return "Web"
        }
        
    }

    var icon: Icon {
        switch self {
        case .games:
            return .default(icon: .applicationsGames)
        case .web:
            return .default(icon: .gtkIconBrowser4)
        }
    }

    @ViewBuilder
    func view() -> Body {
        switch self {
        case .games:
            GamesView()
        case .web:
            WebView()
        }
    }
}






