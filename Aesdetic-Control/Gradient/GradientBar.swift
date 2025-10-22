import SwiftUI

public enum DragPhase {
    case changed
    case ended
}

struct GradientBar: View {
    @Binding var gradient: LEDGradient
    @Binding var selectedStopId: UUID?

    var onTapStop: (UUID) -> Void
    var onTapAnywhere: (_ t: Double, _ tappedStopId: UUID?) -> Void
    var onStopsChanged: (_ stops: [GradientStop], _ phase: DragPhase) -> Void

    private let railHeight: CGFloat = 44
    private let handleWidth: CGFloat = 22
    private let handleHeight: CGFloat = 44
    private let epsilon: Double = 0.0001

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Rail background with current gradient
                LinearGradient(
                    gradient: Gradient(stops: gradient.stops.map { .init(color: $0.color, location: $0.position) }),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.25), lineWidth: 1))
                .contentShape(Rectangle())
                .onTapGesture { location in
                    let w = max(1, geo.size.width - handleWidth)
                    let x = min(max(0, location.x - handleWidth / 2), w)
                    let t = Double(x / w)
                    // Insert new stop at tap position (white by default)
                    let new = GradientStop(position: t, hexColor: "FFFFFF")
                    gradient.stops.append(new)
                    onTapAnywhere(t, nil)
                }

                ForEach(gradient.stops) { stop in
                    let w = max(1, geo.size.width - handleWidth)
                    let x = CGFloat(stop.position) * w

                    handle(for: stop)
                        .position(x: handleWidth / 2 + x, y: geo.size.height / 2)
                        .gesture(
                            DragGesture(minimumDistance: 5)
                                .onChanged { g in
                                    let nx = max(0, min(w, g.location.x - handleWidth / 2))
                                    if let idx = gradient.stops.firstIndex(where: { $0.id == stop.id }) {
                                        gradient.stops[idx].position = Double(nx / w)
                                        onStopsChanged(gradient.stops, .changed)
                                    }
                                }
                                .onEnded { _ in
                                    // Sort once and nudge equals
                                    gradient.stops.sort { $0.position < $1.position }
                                    var last: Double? = nil
                                    for i in 0..<gradient.stops.count {
                                        if let l = last, abs(gradient.stops[i].position - l) < epsilon {
                                            gradient.stops[i].position = min(1.0, l + epsilon)
                                        }
                                        last = gradient.stops[i].position
                                    }
                                    onStopsChanged(gradient.stops, .ended)
                                }
                                .exclusively(before: 
                                    TapGesture(count: 1)
                                        .onEnded {
                                            print("🔵 Single tap detected on stop \(stop.id)")
                                            selectedStopId = stop.id
                                            onTapStop(stop.id)
                                        }
                                )
                                .exclusively(before:
                                    TapGesture(count: 2)
                                        .onEnded {
                                            print("🔴 Double tap detected on stop \(stop.id)")
                                            // Remove via double-tap (leave at least one stop)
                                            if gradient.stops.count > 1 {
                                                gradient.stops.removeAll { $0.id == stop.id }
                                                onStopsChanged(gradient.stops, .ended)
                                            }
                                        }
                                )
                        )
                        .contextMenu {
                            Button(role: .destructive) {
                                if gradient.stops.count > 1 {
                                    gradient.stops.removeAll { $0.id == stop.id }
                                    onStopsChanged(gradient.stops, .ended)
                                }
                            } label: {
                                Label("Remove Stop", systemImage: "trash")
                            }
                        }
                }
            }
            .frame(height: railHeight)
            .animation(nil, value: gradient.stops)
        }
        .frame(height: railHeight)
    }

    private func handle(for stop: GradientStop) -> some View {
        let isSelected = selectedStopId == stop.id
        
        return RoundedRectangle(cornerRadius: 8)
            .fill(stop.color)
            .frame(width: handleWidth, height: handleHeight)
            .shadow(
                color: .black.opacity(0.3), 
                radius: isSelected ? 6 : 3, 
                x: 0, 
                y: isSelected ? 4 : 2
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.6), lineWidth: 1)
            )
            .scaleEffect(isSelected ? 1.1 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isSelected)
            .accessibilityLabel("Gradient stop")
            .accessibilityHint("Drag to reposition. Tap to edit. Double-tap to remove.")
    }
}

#if DEBUG
struct GradientBar_Previews: PreviewProvider {
    @State static var g = LEDGradient(stops: [
        GradientStop(position: 0.0, hexColor: "FF0000"),
        GradientStop(position: 0.5, hexColor: "00FF00"),
        GradientStop(position: 1.0, hexColor: "0000FF")
    ])
    @State static var sel: UUID? = nil

    static var previews: some View {
        GradientBar(
            gradient: $g,
            selectedStopId: $sel,
            onTapStop: { _ in },
            onTapAnywhere: { _, _ in },
            onStopsChanged: { _, _ in }
        )
        .padding()
        .background(Color.black)
        .previewLayout(.sizeThatFits)
    }
}
#endif


