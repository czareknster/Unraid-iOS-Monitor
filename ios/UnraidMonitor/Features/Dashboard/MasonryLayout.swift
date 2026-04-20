import SwiftUI

/// Columns-first grid: each subview is placed in the currently shortest
/// column so cards pack tightly without vertical gaps.
struct MasonryLayout: Layout {
    var columns: Int
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        let heights = columnHeights(for: width, subviews: subviews)
        return CGSize(width: width, height: heights.max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let columnWidth = self.columnWidth(for: bounds.width)
        var heights = Array(repeating: CGFloat(0), count: max(columns, 1))
        for view in subviews {
            let size = view.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))
            let col = heights.enumerated().min(by: { $0.element < $1.element })!.offset
            let x = bounds.minX + CGFloat(col) * (columnWidth + spacing)
            let y = bounds.minY + heights[col]
            view.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: columnWidth, height: size.height)
            )
            heights[col] += size.height + spacing
        }
    }

    private func columnWidth(for totalWidth: CGFloat) -> CGFloat {
        guard columns > 0 else { return totalWidth }
        return (totalWidth - spacing * CGFloat(columns - 1)) / CGFloat(columns)
    }

    private func columnHeights(for width: CGFloat, subviews: Subviews) -> [CGFloat] {
        let columnWidth = self.columnWidth(for: width)
        var heights = Array(repeating: CGFloat(0), count: max(columns, 1))
        for view in subviews {
            let size = view.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))
            let col = heights.enumerated().min(by: { $0.element < $1.element })!.offset
            heights[col] += size.height + spacing
        }
        return heights
    }
}
