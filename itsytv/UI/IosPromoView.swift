import SwiftUI

#if !APPSTORE
private enum IosPromoWindowLayout {
    static let width: CGFloat = 600
    static let initialHeight: CGFloat = 700
}

struct IosPromoView: View {
    @State private var dontShowAgain = true
    @State private var showingQR = false
    var onDismiss: () -> Void
    weak var window: NSWindow?

    private let appStoreURL = "https://apps.apple.com/app/itsytv/id6759216148"

    var body: some View {
        VStack(spacing: 24) {
            // Close button row
            HStack {
                if showingQR {
                    Button {
                        showingQR = false
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Color.secondary.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, -20)
                }
                Spacer()
                Button {
                    savePref()
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.secondary.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .padding(.trailing, -20)
            }

            if showingQR {
                qrCodeView
            } else {
                promoView
            }
        }
        .padding(.top, 20)
        .padding(.horizontal, 50)
        .padding(.bottom, 50)
        .frame(width: IosPromoWindowLayout.width)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .onChange(of: showingQR) { _, _ in
            guard let window = window,
                  let hostingView = window.contentView as? NSHostingView<IosPromoView> else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                let newHeight = hostingView.fittingSize.height
                let oldFrame = window.frame
                let newFrame = NSRect(
                    x: oldFrame.origin.x,
                    y: oldFrame.maxY - newHeight,
                    width: oldFrame.width,
                    height: newHeight
                )
                window.animator().setFrame(newFrame, display: true)
            }
        }
    }

    private var promoView: some View {
        VStack(spacing: 24) {
            // Hero image
            Image("itsytv-ios-promo")
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 300)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            // Text
            VStack(spacing: 8) {
                Text("Itsytv for iPhone and iPad")
                    .font(.system(size: 20, weight: .bold))

                Text("The same Apple TV remote you love on your Mac – now in your pocket. Control playback, navigate apps, and type with your phone keyboard.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // CTA
            VStack(spacing: 10) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showingQR = true
                    }
                } label: {
                    Text("Get on the App Store")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            Capsule().fill(Color.accentColor)
                        )
                }
                .buttonStyle(.plain)

                Button {
                    savePref()
                    onDismiss()
                } label: {
                    Text("Maybe later")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }

            // Checkbox
            Toggle("Don't show again", isOn: $dontShowAgain)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }

    private var qrCodeView: some View {
        VStack(spacing: 24) {
            Text("Scan with your iPhone")
                .font(.system(size: 20, weight: .bold))

            Text("Open your camera app and point it at this QR code to download Itsytv from the App Store.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            if let qrImage = generateQRCode(from: appStoreURL) {
                Image(nsImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Checkbox
            Toggle("Don't show again", isOn: $dontShowAgain)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }

    private func generateQRCode(from string: String) -> NSImage? {
        guard let data = string.data(using: .utf8),
              let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let ciImage = filter.outputImage else { return nil }
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let rep = NSCIImageRep(ciImage: scaled)
        let nsImage = NSImage(size: rep.size)
        nsImage.addRepresentation(rep)
        return nsImage
    }

    private func savePref() {
        if dontShowAgain {
            UserDefaults.standard.set(true, forKey: "iosPromoDismissed")
        }
    }
}

enum IosPromoHelper {
    private static let dismissedKey = "iosPromoDismissed"

    static var shouldShow: Bool {
        !UserDefaults.standard.bool(forKey: dismissedKey)
    }

    static func showIfNeeded() {
        guard shouldShow else { return }

        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: IosPromoWindowLayout.width,
                height: IosPromoWindowLayout.initialHeight
            ),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        let hostingView = NSHostingView(rootView: IosPromoView(
            onDismiss: { window.close() },
            window: window
        ))
        window.contentView = hostingView
        let fittingSize = hostingView.fittingSize
        window.setContentSize(
            NSSize(
                width: IosPromoWindowLayout.width,
                height: fittingSize.height
            )
        )
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
#endif
