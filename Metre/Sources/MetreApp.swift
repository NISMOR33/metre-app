import SwiftUI
import UIKit

// MARK: - Modèle

struct Building: Identifiable, Codable {
    var id = UUID()
    var name: String
    var qty: Int = 0
}

final class Store: ObservableObject {
    @Published var buildings: [Building] { didSet { save() } }
    @Published var step = 1
    @Published var minus = false
    private var history: [(UUID, Int)] = []
    private let key = "metre-buildings"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([Building].self, from: data), !saved.isEmpty {
            buildings = saved
        } else {
            buildings = ["A", "B", "C"].map { Building(name: $0) }
        }
    }

    var total: Int { buildings.reduce(0) { $0 + $1.qty } }

    private func save() {
        if let data = try? JSONEncoder().encode(buildings) { UserDefaults.standard.set(data, forKey: key) }
    }

    func tap(_ b: Building) {
        guard let i = buildings.firstIndex(where: { $0.id == b.id }) else { return }
        let new = max(0, buildings[i].qty + (minus ? -step : step))
        guard new != buildings[i].qty else { Haptic.warning(); return }
        history.append((b.id, buildings[i].qty))
        withAnimation(.snappy) { buildings[i].qty = new }
        minus ? Haptic.impact(.rigid) : Haptic.impact(step >= 10 ? .heavy : .medium)
    }

    func undo() {
        guard let h = history.popLast(), let i = buildings.firstIndex(where: { $0.id == h.0 }) else { Haptic.warning(); return }
        withAnimation(.snappy) { buildings[i].qty = h.1 }
        Haptic.impact(.light)
    }

    func resetAll() {
        withAnimation(.snappy) { for i in buildings.indices { buildings[i].qty = 0 } }
        history.removeAll()
        Haptic.success()
    }

    func add(_ name: String) {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        withAnimation(.snappy) { buildings.append(Building(name: n)) }
        Haptic.success()
    }

    func delete(_ b: Building) {
        withAnimation(.snappy) { buildings.removeAll { $0.id == b.id } }
        Haptic.impact(.rigid)
    }

    func nextName() -> String {
        let used = Set(buildings.map(\.name))
        return "ABCDEFGHIJKLMNOPQRSTUVWXYZ".map(String.init).first { !used.contains($0) } ?? "B\(buildings.count + 1)"
    }
}

// MARK: - Haptique

enum Haptic {
    static func impact(_ s: UIImpactFeedbackGenerator.FeedbackStyle) { UIImpactFeedbackGenerator(style: s).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}

// MARK: - Liquid Glass (iOS 26) avec repli matériau pour iOS 17+

extension View {
    @ViewBuilder func glass(_ radius: CGFloat = 28) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: radius))
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(.white.opacity(0.28), lineWidth: 1))
        }
    }
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Vues

struct BuildingTile: View {
    let b: Building
    let editing: Bool
    @EnvironmentObject var store: Store

    var body: some View {
        Button { if !editing { store.tap(b) } } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text(String(b.name.prefix(2)).uppercased())
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(.systemBackground))
                    .frame(width: 44, height: 44)
                    .background(Color.primary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text("Bâtiment \(b.name)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary).lineLimit(1).padding(.top, 10)
                Spacer(minLength: 6)
                Text("\(b.qty)")
                    .font(.system(size: 46, weight: .heavy, design: .rounded))
                    .monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
                    .contentTransition(.numericText(value: Double(b.qty)))
            }
            .foregroundStyle(.primary)
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 168, alignment: .leading)
            .glass()
        }
        .buttonStyle(PressStyle())
        .overlay(alignment: .topTrailing) {
            if editing {
                Button { store.delete(b) } label: {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(.systemBackground))
                        .frame(width: 30, height: 30).background(Color.primary, in: Circle())
                }
                .offset(x: 6, y: -6)
            }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var store: Store
    @State private var editing = false
    @State private var showAdd = false
    @State private var newName = ""
    @State private var confirmReset = false

    var body: some View {
        ZStack {
            background
            ScrollView {
                VStack(spacing: 16) {
                    header
                    totalCard
                    stepPicker
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                        ForEach(store.buildings) { BuildingTile(b: $0, editing: editing) }
                        addTile
                    }
                    actions
                }
                .padding(16)
            }
        }
        .alert("Nouveau bâtiment", isPresented: $showAdd) {
            TextField("Nom", text: $newName)
            Button("Créer") { store.add(newName) }
            Button("Annuler", role: .cancel) {}
        }
        .confirmationDialog("Tout remettre à 0 ?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Remettre à 0", role: .destructive) { store.resetAll() }
        }
    }

    var background: some View {
        ZStack {
            Color(.systemBackground)
            Circle().fill(Color.primary.opacity(0.22)).frame(width: 320).blur(radius: 80).offset(x: -140, y: -280)
            Circle().fill(Color.primary.opacity(0.14)).frame(width: 300).blur(radius: 80).offset(x: 150, y: 60)
            Circle().fill(Color.primary.opacity(0.18)).frame(width: 320).blur(radius: 90).offset(x: -90, y: 330)
        }
        .ignoresSafeArea()
    }

    var header: some View {
        HStack {
            Text("Métré").font(.system(size: 36, weight: .heavy, design: .rounded))
            Spacer()
            Button(editing ? "Terminé" : "Modifier") { withAnimation(.snappy) { editing.toggle() }; Haptic.impact(.light) }
                .font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                .padding(.horizontal, 16).padding(.vertical, 9).glass(22)
        }
        .padding(.horizontal, 4)
    }

    var totalCard: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Total tous bâtiments").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            Text("\(store.total)")
                .font(.system(size: 68, weight: .heavy, design: .rounded)).monospacedDigit()
                .minimumScaleFactor(0.5).lineLimit(1)
                .contentTransition(.numericText(value: Double(store.total)))
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(22).glass(30)
    }

    var stepPicker: some View {
        HStack(spacing: 4) {
            ForEach([1, 5, 10, 50], id: \.self) { n in
                segment("+\(n)", on: !store.minus && store.step == n) { store.step = n; store.minus = false }
            }
            segment("−\(store.step)", on: store.minus) { store.minus.toggle() }
        }
        .padding(4).glass(20)
    }

    func segment(_ t: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button { withAnimation(.snappy) { action() }; Haptic.impact(.light) } label: {
            Text(t).font(.system(size: 15, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity).padding(.vertical, 11)
                .foregroundStyle(on ? Color(.systemBackground) : .secondary)
                .background(on ? Color.primary : .clear, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    var addTile: some View {
        Button { newName = store.nextName(); showAdd = true; Haptic.impact(.light) } label: {
            VStack(spacing: 6) {
                Image(systemName: "plus").font(.system(size: 30, weight: .light))
                Text("Nouveau bâtiment").font(.subheadline.weight(.bold))
            }
            .foregroundStyle(.primary).frame(maxWidth: .infinity, minHeight: 168)
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [6, 6])))
        }
        .buttonStyle(PressStyle())
    }

    var actions: some View {
        HStack(spacing: 10) {
            Button { store.undo() } label: { Text("Annuler").frame(maxWidth: .infinity).padding(.vertical, 15) }.glass(20)
            Button { confirmReset = true } label: { Text("Tout remettre à 0").frame(maxWidth: .infinity).padding(.vertical, 15) }.glass(20)
        }
        .font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(.primary)
        .buttonStyle(PressStyle())
    }
}

@main
struct MetreApp: App {
    @StateObject private var store = Store()
    var body: some Scene {
        WindowGroup { ContentView().environmentObject(store) }
    }
}
