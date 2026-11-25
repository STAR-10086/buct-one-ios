import BuctModel
import SwiftUI
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        .portrait
    }
}

@main
struct BuctOneApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(environment)
                .preferredColorScheme(environment.preferredColorScheme)
                .task {
                    await environment.bootstrap()
                }
        }
    }
}

struct RootTabView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        @Bindable var env = environment

        GeometryReader { proxy in
            TabView(selection: $env.selectedTab) {
                Tab("课表", systemImage: "calendar", value: AppTab.schedule) {
                    SchedulePlaceholderView()
                }

                Tab("成绩", systemImage: "chart.line.uptrend.xyaxis", value: AppTab.grades) {
                    GradesPlaceholderView()
                }

                Tab("工作台", systemImage: "square.grid.2x2.fill", value: AppTab.workbench) {
                    WorkbenchView()
                }

                Tab("作业", systemImage: "checklist", value: AppTab.homework) {
                    HomeworkPlaceholderView()
                }

                Tab("我的", systemImage: "person.crop.circle", value: AppTab.settings) {
                    SettingsView()
                }
            }
            .tabBarMinimizeBehavior(.onScrollDown)
            .onAppear {
                let width = Int(proxy.size.width)
                let height = Int(proxy.size.height)
                if width > 0 && height > 0 {
                    environment.screenSizeText = "\(width)x\(height)"
                }
            }
        }
    }
}
