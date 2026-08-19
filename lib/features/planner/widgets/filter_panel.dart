import 'package:flutter/material.dart';

import '../../../models/board_filter.dart';
import '../../../models/planner_models.dart';
import '../../../shared/utils/planner_colors.dart';
import '../../../shared/utils/text_rules.dart';

/// The search bar: a text box, a chip for each active filter, and a dropdown
/// holding Filters, Group By, and Favorites side by side.
///
/// Modelled on Odoo's search view, and for the same reason — a board with
/// hundreds of tasks needs more than one text box, but a row of permanent
/// dropdowns eats the header. Folding them into one panel keeps the bar quiet
/// until someone opens it, while the chips keep the *active* search visible at
/// all times, which is the part that matters: a filtered board that does not
/// say it is filtered reads as a board with missing tasks.
class FilterBar extends StatefulWidget {
  const FilterBar({
    super.key,
    required this.search,
    required this.filters,
    required this.savedViews,
    required this.controller,
    required this.onChanged,
    required this.onSaveView,
    required this.onDeleteView,
    required this.onApplyView,
    required this.onSetDefaultView,
    required this.taskOrder,
    required this.onTaskOrderChanged,
  });

  final BoardSearch search;
  final List<BoardFilter> filters;
  final List<SavedView> savedViews;
  final TextEditingController controller;
  final ValueChanged<BoardSearch> onChanged;

  /// Sort lives here too, rather than in its own toolbar button.
  ///
  /// It is a genuinely different operation from Group By — sorting orders
  /// tasks *within* a bucket, grouping decides what the buckets are — but both
  /// answer "how do I want to look at this board", so they belong behind the
  /// same control instead of at opposite ends of two rows.
  final TaskOrder taskOrder;
  final ValueChanged<TaskOrder> onTaskOrderChanged;

  /// Name and default flag; the search itself is whatever is active.
  final void Function(String name, bool isDefault) onSaveView;
  final ValueChanged<SavedView> onDeleteView;
  final ValueChanged<SavedView> onApplyView;

  /// Flips whether an already-saved filter applies itself when the board
  /// opens — so a favourite does not have to be re-saved to become one.
  final void Function(SavedView view, bool isDefault) onSetDefaultView;

  @override
  State<FilterBar> createState() => _FilterBarState();
}

class _FilterBarState extends State<FilterBar> {
  final MenuController _menu = MenuController();
  final ScrollController _chipScroll = ScrollController();
  final FocusNode _fieldFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    // The whole bar reacts to focus, rather than the text box alone drawing
    // its own ring inside a container that stays inert.
    _fieldFocus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _chipScroll.dispose();
    _fieldFocus.dispose();
    super.dispose();
  }

  BoardFilter? _filterById(String id) {
    for (final filter in widget.filters) {
      if (filter.id == id) return filter;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final search = widget.search;

    final active = search.chipCount > 0;
    final focused = _fieldFocus.hasFocus;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      height: 34,
      decoration: BoxDecoration(
        // One surface, one border. The bar was a grey box holding a *white*
        // TextField — the app theme fills every input with plannerCard — so
        // a pale rectangle sat inside a grey frame and the two shades fought.
        // The field's own fill is switched off below; this is the only ground.
        color: focused ? plannerCard : plannerSurface,
        borderRadius: BorderRadius.circular(radiusSm),
        border: Border.all(
          color: focused
              ? plannerBlue
              : (active ? tint(plannerBlue, 0.45) : plannerBorder),
          width: focused ? 1.4 : 1,
        ),
      ),
      padding: const EdgeInsets.only(left: 10, right: 4),
      child: Row(
        children: [
          Icon(
            Icons.search_rounded,
            size: 15,
            color: focused ? plannerBlue : plannerFaint,
          ),
          const SizedBox(width: 8),

          // Chips sit inside the bar rather than on a row of their own, so a
          // filtered board does not change height and shift everything below.
          if (search.chipCount > 0) ...[
            // Capped and scrollable. A Flexible(flex: 0) still demands the
            // chips' full natural width, so three active filters shoved the
            // text box and the Filter button off the end of the bar.
            Flexible(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                // Its own controller: several of these can live in one route
                // and the inherited PrimaryScrollController asserts when more
                // than one position attaches to it.
                controller: _chipScroll,
                primary: false,
                child: Row(
                  children: [
                    for (final id in search.filterIds)
                      if (_filterById(id) case final filter?)
                        _Chip(
                          icon: Icons.filter_alt_outlined,
                          label: filter.label,
                          color: plannerBlue,
                          onRemove: () => widget.onChanged(search.remove(id)),
                        ),
                    if (search.groupBy != GroupBy.none)
                      _Chip(
                        icon: Icons.layers_outlined,
                        label: search.groupBy.label,
                        color: plannerTeal,
                        onRemove: () => widget.onChanged(
                          search.copyWith(groupBy: GroupBy.none),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 4),
          ],

          // Expanded, so the field takes whatever the chips and the button
          // leave rather than asking for a width of its own. A ConstrainedBox
          // here has no bounded width to work from inside a Row and overflows.
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _fieldFocus,
              // Emoji are stripped here as everywhere outside chat: a search
              // term containing one can never match a task name, which cannot.
              inputFormatters: [emojiFreeFormatter],
              style: const TextStyle(fontSize: 13),
              cursorColor: plannerBlue,
              cursorHeight: 15,
              decoration: InputDecoration(
                isDense: true,
                // filled:false, and every border cleared. The theme fills
                // inputs white and Material paints hover and focus overlays
                // on top — all of it landing as a lighter rectangle inside
                // this bar. The container above is the whole visual.
                filled: false,
                fillColor: Colors.transparent,
                hoverColor: Colors.transparent,
                focusColor: Colors.transparent,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: active ? '' : 'Search tasks…',
                hintStyle: const TextStyle(color: plannerFaint, fontSize: 13),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
              onChanged: (value) =>
                  widget.onChanged(search.copyWith(query: value)),
            ),
          ),

          if (search.chipCount > 0 || widget.controller.text.isNotEmpty)
            _IconButton(
              icon: Icons.close_rounded,
              tooltip: 'Clear',
              onTap: () {
                widget.controller.clear();
                widget.onChanged(const BoardSearch());
              },
            ),

          MenuAnchor(
            controller: _menu,
            alignmentOffset: const Offset(0, 6),
            style: MenuStyle(
              padding: WidgetStateProperty.all(EdgeInsets.zero),
              backgroundColor: WidgetStateProperty.all(plannerCard),
              // Lifted off the page rather than outlined against it. A hairline
              // border alone left the panel looking pasted onto the toolbar.
              elevation: WidgetStateProperty.all(10),
              shadowColor: WidgetStateProperty.all(
                plannerInk.withValues(alpha: 0.18),
              ),
              shape: WidgetStateProperty.all(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(radiusLg),
                  side: const BorderSide(color: plannerBorder),
                ),
              ),
            ),
            menuChildren: [
              _FilterMenu(
                search: search,
                taskOrder: widget.taskOrder,
                onTaskOrderChanged: widget.onTaskOrderChanged,
                filters: widget.filters,
                savedViews: widget.savedViews,
                onChanged: widget.onChanged,
                onSaveView: widget.onSaveView,
                onDeleteView: widget.onDeleteView,
                onApplyView: widget.onApplyView,
                onSetDefaultView: widget.onSetDefaultView,
                onClose: _menu.close,
              ),
            ],
            builder: (context, controller, child) => _FilterButton(
              open: controller.isOpen,
              count: search.chipCount,
              onTap: () =>
                  controller.isOpen ? controller.close() : controller.open(),
            ),
          ),
        ],
      ),
    );
  }
}

/// The control that opens the panel.
///
/// A labelled button rather than the bare chevron it started as: an arrow
/// tucked inside a search box reads as decoration, and the entire filter
/// feature was invisible behind it.
class _FilterButton extends StatefulWidget {
  const _FilterButton({
    required this.open,
    required this.count,
    required this.onTap,
  });

  final bool open;
  final int count;
  final VoidCallback onTap;

  @override
  State<_FilterButton> createState() => _FilterButtonState();
}

class _FilterButtonState extends State<_FilterButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.count > 0 || widget.open;

    return Tooltip(
      message: 'Filters, grouping and saved views',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            height: 26,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              // Card white on the bar's grey, so the button reads as raised.
              // Both were plannerSurface before, which made the button vanish
              // into the field it sits in.
              color: active
                  ? tint(plannerBlue, 0.12)
                  : (_hovered ? Colors.white : plannerCard),
              borderRadius: BorderRadius.circular(radiusXs),
              border: Border.all(
                color: active ? Colors.transparent : plannerBorder,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.tune_rounded,
                  size: 14,
                  color: active ? plannerBlue : plannerMuted,
                ),
                const SizedBox(width: 5),
                Text(
                  'Filter',
                  style: TextStyle(
                    color: active ? plannerBlue : plannerText,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 3),
                Icon(
                  widget.open
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 14,
                  color: active ? plannerBlue : plannerMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One active filter, shown in the bar with a way to take it off.
class _Chip extends StatelessWidget {
  const _Chip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onRemove,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.only(left: 5, right: 2, top: 2, bottom: 2),
      decoration: BoxDecoration(
        color: tint(color, 0.10),
        borderRadius: BorderRadius.circular(radiusXs),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 2),
          InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(radiusXs),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Icon(Icons.close_rounded, size: 12, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// The three columns.
class _FilterMenu extends StatelessWidget {
  const _FilterMenu({
    required this.search,
    required this.taskOrder,
    required this.onTaskOrderChanged,
    required this.filters,
    required this.savedViews,
    required this.onChanged,
    required this.onSaveView,
    required this.onDeleteView,
    required this.onApplyView,
    required this.onSetDefaultView,
    required this.onClose,
  });

  final BoardSearch search;
  final TaskOrder taskOrder;
  final ValueChanged<TaskOrder> onTaskOrderChanged;
  final List<BoardFilter> filters;
  final List<SavedView> savedViews;
  final ValueChanged<BoardSearch> onChanged;
  final void Function(String name, bool isDefault) onSaveView;
  final ValueChanged<SavedView> onDeleteView;
  final ValueChanged<SavedView> onApplyView;
  final void Function(SavedView view, bool isDefault) onSetDefaultView;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    // Grouped so a divider can separate each kind, the way Odoo separates its
    // filter families. Without the rules the column is an undifferentiated list
    // and the union-within-a-kind behaviour has nothing to hint at it.
    final byKind = <FilterKind, List<BoardFilter>>{};
    for (final filter in filters) {
      byKind.putIfAbsent(filter.kind, () => []).add(filter);
    }

    final sections =
        <({IconData icon, String title, Color color, Widget body})>[
          (
            icon: Icons.filter_alt_outlined,
            title: 'Filters',
            color: plannerBlue,
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (index, entry) in byKind.entries.indexed) ...[
                  if (index > 0)
                    const Divider(height: 15, color: plannerDivider),
                  for (final filter in entry.value)
                    _MenuRow(
                      label: filter.label,
                      selected: search.filterIds.contains(filter.id),
                      // Stays open: picking two filters is the normal case, and
                      // closing after each one would make it tedious.
                      onTap: () => onChanged(search.toggle(filter.id)),
                    ),
                ],
              ],
            ),
          ),
          (
            icon: Icons.layers_outlined,
            title: 'Group By',
            color: plannerTeal,
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final group in GroupBy.values)
                  if (group != GroupBy.none)
                    _MenuRow(
                      label: group.label,
                      selected: search.groupBy == group,
                      onTap: () => onChanged(search.withGroup(group)),
                    ),
              ],
            ),
          ),
          (
            icon: Icons.swap_vert_rounded,
            title: 'Sort',
            color: plannerViolet,
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final order in TaskOrder.values)
                  _MenuRow(
                    label: order.label,
                    selected: taskOrder == order,
                    onTap: () => onTaskOrderChanged(order),
                  ),
              ],
            ),
          ),
          (
            icon: Icons.star_outline_rounded,
            title: 'Favorites',
            color: plannerYellow,
            body: _Favorites(
              search: search,
              savedViews: savedViews,
              onSaveView: onSaveView,
              onDeleteView: onDeleteView,
              onSetDefaultView: onSetDefaultView,
              onApplyView: (view) {
                onApplyView(view);
                onClose();
              },
            ),
          ),
        ];

    // Sized against the real window. Four fixed columns need ~880px; below that
    // the panel hung off the left edge of the screen and ran past the bottom,
    // because a MenuAnchor positions from its button and does not clamp a child
    // that does not fit.
    final screen = MediaQuery.sizeOf(context);
    final wide = screen.width >= 940;

    if (!wide) {
      // Stacked. Four columns at this width would be slivers too narrow to
      // read, so they become sections in one scrolling list instead.
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: screen.width - 32,
          maxHeight: (screen.height - 190).clamp(260.0, 520.0),
        ),
        child: SingleChildScrollView(
          // Off the primary controller. The chip strip in the bar above is
          // also a scroll view on the same route, and two positions attached
          // to PrimaryScrollController makes the scrollbar assert.
          primary: false,
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (index, section) in sections.indexed) ...[
                if (index > 0) const Divider(height: 1, color: plannerDivider),
                _Column(
                  icon: section.icon,
                  title: section.title,
                  color: section.color,
                  width: double.infinity,
                  scrollable: false,
                  child: section.body,
                ),
              ],
            ],
          ),
        ),
      );
    }

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 880,
        maxHeight: (screen.height - 200).clamp(280.0, 460.0),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (index, section) in sections.indexed) ...[
              if (index > 0)
                const VerticalDivider(width: 1, color: plannerDivider),
              _Column(
                icon: section.icon,
                title: section.title,
                color: section.color,
                width: 214,
                child: section.body,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Column extends StatefulWidget {
  const _Column({
    required this.icon,
    required this.title,
    required this.color,
    required this.child,
    this.width = 214,
    this.scrollable = true,
  });

  final IconData icon;
  final String title;
  final Color color;
  final Widget child;
  final double width;

  /// False in the stacked layout, where one outer scroll view wraps every
  /// section — nesting a second scrollable inside it would trap the gesture.
  final bool scrollable;

  @override
  State<_Column> createState() => _ColumnState();
}

class _ColumnState extends State<_Column> {
  // Owned here rather than created in build: a controller made fresh each
  // frame never gets disposed, and each one attaches to the scroll position.
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            // The heading icon sits on a tinted disc, so each column reads as
            // its own thing at a glance rather than four identical lists.
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: tint(widget.color, 0.12),
                borderRadius: BorderRadius.circular(radiusXs),
              ),
              alignment: Alignment.center,
              child: Icon(widget.icon, size: 13, color: widget.color),
            ),
            const SizedBox(width: 9),
            Text(
              widget.title,
              style: const TextStyle(
                color: plannerInk,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        widget.child,
      ],
    );

    return SizedBox(
      width: widget.width,
      child: widget.scrollable
          ? SingleChildScrollView(
              // Its own controller. All four columns are scrollables inside one
              // menu, so leaving them on the inherited PrimaryScrollController
              // attaches four positions to it and the scrollbar asserts.
              controller: _scroll,
              primary: false,
              padding: const EdgeInsets.fromLTRB(14, 15, 14, 16),
              child: content,
            )
          : Padding(
              padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
              child: content,
            ),
    );
  }
}

/// One selectable line, with a tick when active.
class _MenuRow extends StatefulWidget {
  const _MenuRow({
    required this.label,
    required this.selected,
    required this.onTap,
    this.trailing,
    this.alwaysShowTrailing = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget? trailing;

  /// Keeps [trailing] on screen instead of revealing it on hover. The
  /// favourites star is state, not an action: which filter opens the board
  /// has to be readable without pointing at every row to find out.
  final bool alwaysShowTrailing;

  @override
  State<_MenuRow> createState() => _MenuRowState();
}

class _MenuRowState extends State<_MenuRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(
            color: _hovered ? plannerHover : Colors.transparent,
            borderRadius: BorderRadius.circular(radiusXs),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 17,
                child: widget.selected
                    ? const Icon(
                        Icons.check_rounded,
                        size: 14,
                        color: plannerBlue,
                      )
                    : null,
              ),
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: widget.selected ? plannerBlue : plannerText,
                    fontSize: 12.5,
                    fontWeight: widget.selected
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                ),
              ),
              // Shown on hover only, unless the row asks otherwise. A delete
              // button on every row is visual noise and an easy misclick; it
              // also needs its width back for the label, which is what
              // overflowed the column.
              if (widget.trailing != null &&
                  (_hovered || widget.alwaysShowTrailing))
                widget.trailing!,
            ],
          ),
        ),
      ),
    );
  }
}

/// Saved searches, and the form for adding one.
class _Favorites extends StatefulWidget {
  const _Favorites({
    required this.search,
    required this.savedViews,
    required this.onSaveView,
    required this.onDeleteView,
    required this.onApplyView,
    required this.onSetDefaultView,
  });

  final BoardSearch search;
  final List<SavedView> savedViews;
  final void Function(String name, bool isDefault) onSaveView;
  final ValueChanged<SavedView> onDeleteView;
  final ValueChanged<SavedView> onApplyView;
  final void Function(SavedView view, bool isDefault) onSetDefaultView;

  @override
  State<_Favorites> createState() => _FavoritesState();
}

/// Mirrors board_views_name_length in 0002_core.sql, which checks
/// `char_length(trim(name)) between 1 and 60`.
const int _maxNameLength = 60;

class _FavoritesState extends State<_Favorites> {
  final TextEditingController _name = TextEditingController();
  bool _expanded = false;
  bool _isDefault = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String? _error;

  void _save() {
    final name = _name.text.trim();
    // Said out loud rather than returning quietly. Clicking Save on an empty
    // field used to do nothing at all, which reads as a broken button.
    if (name.isEmpty) {
      setState(() => _error = 'Give this filter a name.');
      return;
    }
    if (name.length > _maxNameLength) {
      setState(() => _error = 'Keep it under $_maxNameLength characters.');
      return;
    }
    widget.onSaveView(name, _isDefault);
    _name.clear();
    setState(() {
      _expanded = false;
      _isDefault = false;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Nothing worth saving yet, and nothing saved: say so rather than offering
    // a form that would store an empty search.
    final canSave = !widget.search.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.savedViews.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Text(
              'No saved filters yet.',
              style: TextStyle(color: plannerFaint, fontSize: 11.5),
            ),
          )
        else
          for (final view in widget.savedViews)
            _MenuRow(
              label: view.name,
              selected: view.isDefault,
              onTap: () => widget.onApplyView(view),
              // The star is the row's state, so it stays put; delete still
              // waits for hover, one line down.
              alwaysShowTrailing: view.isDefault,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // The default star lives on the row, so a filter saved
                  // yesterday can become the default without re-saving it.
                  _IconButton(
                    icon: view.isDefault
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    color: view.isDefault ? plannerYellow : null,
                    tooltip: view.isDefault
                        ? 'Default — applies when this board opens. '
                              'Click to clear.'
                        : 'Apply automatically when this board opens',
                    onTap: () => widget.onSetDefaultView(view, !view.isDefault),
                  ),
                  _IconButton(
                    icon: Icons.delete_outline_rounded,
                    tooltip: 'Delete',
                    onTap: () => widget.onDeleteView(view),
                  ),
                ],
              ),
            ),

        const Divider(height: 15, color: plannerDivider),

        if (!_expanded)
          _MenuRow(
            label: 'Save current filter',
            selected: false,
            onTap: canSave ? () => setState(() => _expanded = true) : () {},
            trailing: Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 15,
              color: canSave ? plannerMuted : plannerFaint,
            ),
          )
        else ...[
          TextField(
            controller: _name,
            autofocus: true,
            maxLength: _maxNameLength,
            inputFormatters: [emojiFreeFormatter],
            style: const TextStyle(fontSize: 12.5),
            buildCounter:
                (
                  context, {
                  required currentLength,
                  required isFocused,
                  required maxLength,
                }) => null,
            decoration: const InputDecoration(
              isDense: true,
              hintText: 'Name this filter',
              hintStyle: TextStyle(color: plannerFaint, fontSize: 12.5),
              contentPadding: EdgeInsets.symmetric(vertical: 6),
            ),
            onSubmitted: (_) => _save(),
            onChanged: (_) {
              if (_error != null) {
                setState(() => _error = null);
              }
            },
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _error!,
                style: const TextStyle(color: plannerRed, fontSize: 11),
              ),
            ),
          const SizedBox(height: 6),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => setState(() => _isDefault = !_isDefault),
              child: Row(
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: Checkbox(
                      value: _isDefault,
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onChanged: (value) =>
                          setState(() => _isDefault = value ?? false),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Flexible(
                    child: Text(
                      'Use as default',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: plannerText, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _save,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 30),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Save'),
                ),
              ),
              const SizedBox(width: 6),
              TextButton(
                onPressed: () => setState(() {
                  _expanded = false;
                  _name.clear();
                }),
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 30),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _IconButton extends StatefulWidget {
  const _IconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  /// Overrides the resting grey — the favourites star, for one, stays yellow
  /// while it is the active default.
  final Color? color;

  @override
  State<_IconButton> createState() => _IconButtonState();
}

class _IconButtonState extends State<_IconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: _hovered ? plannerHover : Colors.transparent,
              borderRadius: BorderRadius.circular(radiusXs),
            ),
            child: Icon(
              widget.icon,
              size: 15,
              color: widget.color ?? (_hovered ? plannerText : plannerMuted),
            ),
          ),
        ),
      ),
    );
  }
}
