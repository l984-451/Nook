//
//  MemberCard.swift
//  Nook
//
//  Created by Maciek Bagiński on 07/12/2025.
//

import SwiftUI

struct MemberCard: View {
    @Environment(\.openURL) var openURL


    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Nook Member")
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Spacer()
            Text("Thank you")
                .font(.system(size: 32, weight: .bold, design: .serif))
                .foregroundStyle(.white.opacity(0.9))
                .italic()
            Text("For supporting our project")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
            Spacer()

            HStack {
                SocialButon(icon: "github.fill", label: "Source code", action: {
                    openURL(URL(string: "https://github.com/nook-browser/Nook")!)
                })
                SocialButon(icon: "opencollective-fill", label: "Support us", action: {
                    openURL(URL(string: "https://opencollective.com/nook-browser")!)

                })
            }


        }
        .padding(.vertical, 32)
        .frame(width: 250, height: 400)
        .background(
            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                    [0.0, 0.5], [0.5, 0.5], [1.0, 0.5],
                    [0.0, 1.0], [0.5, 1.0], [1.0, 1.0]
                ],
                colors: [
                    .indigo, .purple, .blue,
                    .teal, .cyan, .mint,
                    .blue, .indigo, .purple
                ]
            )
        )
        .clipShape(
            RoundedRectangle(cornerRadius: 14)
        )
    }
}

struct SocialButon: View {
    @State private var isHovered: Bool = false
    var icon: String
    var label: String
    var action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: 4) {
                Image(icon)
                    .font(.system(size: 16, weight: .medium))
                Text(label)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(isHovered ? .white : .white.opacity(0.6))
        }
        .buttonStyle(.plain)
        .onHoverTracking { state in
            isHovered = state
        }
    }
}
