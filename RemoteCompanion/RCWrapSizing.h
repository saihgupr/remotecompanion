#import <UIKit/UIKit.h>

// The height a subtitle-style cell needs to show its whole title and subtitle, and never below
// minHeight. Plain table cells lay their labels out by hand, so the cell is laid out at its real
// width and the label heights UIKit gives (numberOfLines = 0) are read back: one-line text stays
// one line, and only text that really wraps makes the row taller.
static inline CGFloat RCWrappedCellHeight(UITableViewCell *cell, CGFloat targetWidth, CGFloat minHeight) {
    CGFloat width = cell.frame.size.width > 100.0 ? cell.frame.size.width : targetWidth;
    CGRect savedFrame = cell.frame;
    cell.frame = CGRectMake(0, 0, width, 1000.0);
    [cell setNeedsLayout];
    [cell layoutIfNeeded];

    CGFloat titleHeight = cell.textLabel.text.length ? ceil(cell.textLabel.frame.size.height) : 0;
    CGFloat detailHeight = cell.detailTextLabel.text.length ? ceil(cell.detailTextLabel.frame.size.height) : 0;
    cell.frame = savedFrame;

    CGFloat needed = 12.0 + titleHeight + (detailHeight > 0 ? 3.0 + detailHeight : 0.0) + 12.0;
    return MAX(minHeight, needed);
}
