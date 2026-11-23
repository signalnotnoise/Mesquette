//
//  ParameterControlsView.swift
//  Mesquette
//
//  Created by Alexander Otero on 4/24/26.
//
//  Design principles applied (think.design visionOS guide):
//   • Glass / translucent material — lets the real world show through
//   • Bolder typography — readable against complex real-world backgrounds
//   • ≥44–60pt interactive targets — accommodates eye-tracking precision
//   • Hover-effect state indicators — system highlights on gaze
//   • Scrollable body + sticky chrome so controls never clip in a window
//   • Essentials first; advanced folded away until needed

import SwiftUI

// MARK: - Presentation style

/// How the parameter panel is hosted.
enum ParameterControlsStyle: Sendable {
    /// Standalone glass panel (inline / ornament-style).
    case panel
    /// Hosted inside a system sheet — no double glass; fills available height.
    case sheet
}

// MARK: - Main panel

struct ParameterControlsView: View {
    @Bindable var appModel: AppModel
    var style: ParameterControlsStyle = .panel

    /// Query-batch options offered as discrete steps.
    private let batchOptions: [Int] = [512, 1024, 2048, 4096, 8192]
    /// Output batch size options offered as discrete steps.
    private let outputBatchOptions: [Int] = [1, 2, 4]
    /// Marching-cubes grid resolution (Preview 48 … High 128 … up to 512).
    private let gridSizeRange: ClosedRange<Double> = 32...512

    @State private var showAdvanced: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Sheet uses the navigation title; panel keeps its own chrome header.
            if style == .panel {
                header
                Divider().padding(.horizontal, 20)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    essentialsSection

                    SpatialDivider()

                    advancedSection
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: style == .panel ? 420 : .infinity)

            Divider().padding(.horizontal, 20)
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: style == .sheet ? .infinity : nil, alignment: .top)
#if os(visionOS)
        .modifier(ParameterPanelChrome(style: style))
#else
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
#endif
        .disabled(appModel.isGenerating)
    }

    // MARK: - Header / footer

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "slider.horizontal.3")
                .font(.title2)
                .foregroundStyle(.primary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Generation Parameters")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text(appModel.isGenerating ? "Locked while generating" : "Quality first · fine-tune below")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 16)
    }

    private var footer: some View {
        Button {
            appModel.resetGenerationParameters()
            showAdvanced = false
        } label: {
            Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
                .font(.subheadline)
                .fontWeight(.medium)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
        }
        .buttonStyle(.borderless)
        .disabled(appModel.isGenerating)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Essentials (always visible)

    private var essentialsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionLabel("Essentials")

            SpatialPickerRow(
                icon: "speedometer",
                title: "Quality",
                subtitle: appModel.qualityPreset.subtitle,
                options: QualityPreset.allCases,
                selection: $appModel.qualityPreset,
                label: { $0.title },
                disabled: appModel.isGenerating
            )

            SpatialDivider()

            SpatialSliderRow(
                icon: "dial.high",
                title: "Guidance Scale",
                subtitle: "Prompt adherence strength",
                value: $appModel.guidanceScale,
                range: 1.0...30.0,
                displayValue: String(format: "%.1f", appModel.guidanceScale),
                disabled: appModel.isGenerating
            )

            SpatialDivider()

            SpatialSliderRow(
                icon: "waveform.path.ecg",
                title: "Inference Steps",
                subtitle: "Diffusion sampling iterations",
                value: Binding(
                    get: { Double(appModel.numInferenceSteps) },
                    set: { appModel.numInferenceSteps = max(4, Int($0.rounded())) }
                ),
                range: 4.0...256.0,
                displayValue: "\(appModel.numInferenceSteps)",
                disabled: appModel.isGenerating
            )
        }
    }

    // MARK: - Advanced (collapsed by default)

    private var advancedSection: some View {
        DisclosureGroup(isExpanded: $showAdvanced) {
            VStack(alignment: .leading, spacing: 20) {
                SpatialPickerRow(
                    icon: "square.grid.2x2",
                    title: "Output Batch Size",
                    subtitle: "Number of variations to generate",
                    options: outputBatchOptions,
                    selection: $appModel.batchSize,
                    label: { "\($0)" },
                    disabled: appModel.isGenerating
                )

                SpatialDivider()

                SpatialSliderRow(
                    icon: "cube.transparent",
                    title: "Grid Resolution",
                    subtitle: "Marching-cubes voxel grid (32–512)",
                    value: Binding(
                        get: { Double(appModel.gridSize) },
                        set: {
                            appModel.gridSize = max(32, min(512, Int($0.rounded())))
                        }
                    ),
                    range: gridSizeRange,
                    displayValue: "\(appModel.gridSize)",
                    disabled: appModel.isGenerating
                )

                SpatialDivider()

                SpatialPickerRow(
                    icon: "memorychip",
                    title: "Query Batch",
                    subtitle: "GPU occupancy queries per pass",
                    options: batchOptions,
                    selection: $appModel.queryBatchSize,
                    label: { $0 >= 1024 ? "\($0 / 1024)K" : "\($0)" },
                    disabled: appModel.isGenerating
                )

                SpatialDivider()

                SpatialSeedRow(
                    seed: $appModel.seed,
                    disabled: appModel.isGenerating
                )

                SpatialDivider()

                SpatialToggleRow(
                    icon: "square.stack.3d.forward.dottedline",
                    title: "Live Partials",
                    subtitle: "Preview meshes during sampling (slower, higher GPU risk)",
                    isOn: $appModel.enableLivePartials,
                    disabled: appModel.isGenerating
                )

                SpatialToggleRow(
                    icon: "cpu",
                    title: "GPU Final Extract",
                    subtitle: "Metal marching cubes for the final mesh only",
                    isOn: $appModel.usesGPU,
                    disabled: appModel.isGenerating
                )
            }
            .padding(.top, 16)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Advanced")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    Text(showAdvanced
                         ? "Batch, grid, seed, and extract options"
                         : advancedSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .frame(minHeight: 44)
        }
#if os(visionOS)
        .hoverEffect(.highlight)
#endif
    }

    private var advancedSummary: String {
        let partials = appModel.enableLivePartials ? "partials on" : "partials off"
        let gpu = appModel.usesGPU ? "GPU extract" : "CPU extract"
        return "Batch \(appModel.batchSize) · grid \(appModel.gridSize) · seed \(appModel.seed) · \(gpu) · \(partials)"
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .tracking(0.6)
    }
}

// MARK: - Chrome (visionOS)

#if os(visionOS)
private struct ParameterPanelChrome: ViewModifier {
    let style: ParameterControlsStyle

    func body(content: Content) -> some View {
        switch style {
        case .panel:
            content
                .glassBackgroundEffect()
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        case .sheet:
            // System sheet already provides material; keep content plain.
            content
        }
    }
}
#endif

// MARK: - Spatial slider row

/// A single labelled slider row sized for eye-tracking comfort.
private struct SpatialSliderRow: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let displayValue: String
    let disabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .fontWeight(.semibold)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Text(displayValue)
                    .font(.title3)
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
            }

            Slider(value: $value, in: range)
                .frame(minHeight: 32)
                .disabled(disabled)
                .tint(.white.opacity(0.85))
        }
    }
}

// MARK: - Spatial picker row

/// A segmented-style picker row for discrete options.
private struct SpatialPickerRow<Option: Hashable>: View {
    let icon: String
    let title: String
    let subtitle: String
    let options: [Option]
    @Binding var selection: Option
    let label: (Option) -> String
    let disabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .fontWeight(.semibold)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Text(label(selection))
                    .font(.title3)
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
            }

            HStack(spacing: 4) {
                ForEach(options, id: \.self) { option in
                    SpatialSegmentButton(
                        label: label(option),
                        isSelected: selection == option,
                        disabled: disabled
                    ) {
                        selection = option
                    }
                }
            }
            .frame(height: 52)
        }
    }
}

// MARK: - Spatial segment button

/// Individual segment with visionOS hover-effect and nested corner radius.
private struct SpatialSegmentButton: View {
    let label: String
    let isSelected: Bool
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.headline)
                .fontWeight(isSelected ? .bold : .regular)
                .foregroundStyle(isSelected ? .primary : .secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected
                              ? AnyShapeStyle(.regularMaterial)
                              : AnyShapeStyle(.ultraThinMaterial))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            isSelected
                                ? Color.white.opacity(0.35)
                                : Color.clear,
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
#if os(visionOS)
        .hoverEffect(.highlight)
#endif
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - Spatial seed row

/// Seed control: shows current value, a stepper, and a dice button to randomise.
private struct SpatialSeedRow: View {
    @Binding var seed: Int
    let disabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "dice")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Noise Seed")
                        .font(.headline)
                        .fontWeight(.semibold)
                    Text("Base seed; batch uses seed, seed+1, …")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Text("\(seed)")
                    .font(.title3)
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
            }

            HStack(spacing: 4) {
                SpatialSegmentButton(label: "−", isSelected: false, disabled: disabled) {
                    seed = max(0, seed - 1)
                }
                SpatialSegmentButton(label: "+", isSelected: false, disabled: disabled) {
                    seed += 1
                }
                SpatialSegmentButton(label: "+10", isSelected: false, disabled: disabled) {
                    seed += 10
                }
                Button {
                    seed = Int.random(in: 0...999_999)
                } label: {
                    Label("Random", systemImage: "shuffle")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(AnyShapeStyle(.ultraThinMaterial))
                        )
                }
                .buttonStyle(.plain)
                .disabled(disabled)
#if os(visionOS)
                .hoverEffect(.highlight)
#endif
            }
            .frame(height: 52)
        }
    }
}

// MARK: - Spatial toggle row

private struct SpatialToggleRow: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    let disabled: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .fontWeight(.semibold)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .disabled(disabled)
        .tint(.white.opacity(0.85))
        .frame(minHeight: 44)
    }
}

// MARK: - Subtle divider

private struct SpatialDivider: View {
    var body: some View {
        Divider()
            .opacity(0.4)
    }
}

// MARK: - Preview

#Preview {
    ParameterControlsView(appModel: AppModel(), style: .panel)
        .frame(width: 500)
        .padding(40)
        .environment(AppModel())
}
