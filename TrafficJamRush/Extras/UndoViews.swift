import SwiftUI
import GameKit

/// The Undo booster's "buy" dialog: the same layout as the game's booster dialog (PropDialog) for Shuffle / Crane /
/// Sort, with Undo's icon, text and price.
struct ExtrasUndoDialog: View {
    let visible: Bool
    let coins: Int
    let onDismiss: () -> Void
    let onBuy: () -> Void
    let onAd: () -> Void

    static let title = "Undo"
    static let description = "Send the last vehicle you moved back to its spot. Its passengers hop back to the front of the line."

    var body: some View {
        let price = ExtrasRepository.UNDO_PRICE
        GameDialog(visible: visible, onDismiss: onDismiss) {
            GamePanel(Self.title, onClose: onDismiss) {
                GameIcon(Icon.UNDO, 92)
                    .frame(width: 124, height: 124)
                    .background(Color(argb: 0xFFFF_E6C7), in: RoundedRectangle(cornerRadius: 26))
                    .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(Color(argb: 0xFFF3_C98B), lineWidth: 3))
                Spacer().frame(height: 14)
                GText(Self.description, .Body, color: Color(argb: 0xFF8A_4B14), size: 17, align: .center)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer().frame(height: 20)
                HStack(spacing: 12) {
                    GameButton("\(price)", onClick: onBuy, color: ButtonColor.GREEN, fontSize: 22,
                               enabled: coins >= price, leading: CoinBadge.icon(30))
                        .frame(maxWidth: .infinity)
                    GameButton("Free", onClick: onAd, color: ButtonColor.ORANGE, fontSize: 22, leading: AdBadge.icon(30))
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}
