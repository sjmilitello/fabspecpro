//
//  LaunchScreenView.swift
//  FabSpecPro
//

import SwiftUI

struct LaunchScreenView: View {
    @State private var scale: CGFloat = 0.1
    @State private var logoOpacity: Double = 0
    @State private var screenOpacity: Double = 1
    @Binding var isActive: Bool

    private let logoSize: CGFloat = 150
    private var logoCornerRadius: CGFloat { logoSize * 0.22 }
    
    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: logoSize, height: logoSize)
                .clipShape(RoundedRectangle(cornerRadius: logoCornerRadius, style: .continuous))
                .scaleEffect(scale)
                .opacity(logoOpacity)
        }
        .opacity(screenOpacity)
        .onAppear {
            // Fade in and scale up animation (10% to 150% over 1.5 seconds)
            withAnimation(.easeOut(duration: 1.5)) {
                scale = 1.5
                logoOpacity = 1.0
            }
            
            // Hold for 0.5 seconds after animation, then fade out entire screen
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeIn(duration: 0.4)) {
                    screenOpacity = 0
                }
                // Dismiss after fade out completes
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    isActive = false
                }
            }
        }
    }
}
