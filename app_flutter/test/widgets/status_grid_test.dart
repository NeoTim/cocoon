// Copyright (c) 2019 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cocoon_service/protos.dart' show Commit, CommitStatus, Stage, Task;

import 'package:app_flutter/logic/task_matrix.dart' show TaskMatrix;
import 'package:app_flutter/service/cocoon.dart';
import 'package:app_flutter/service/dev_cocoon.dart';
import 'package:app_flutter/state/build.dart';
import 'package:app_flutter/widgets/commit_box.dart';
import 'package:app_flutter/widgets/state_provider.dart';
import 'package:app_flutter/widgets/status_grid.dart';
import 'package:app_flutter/widgets/task_box.dart';
import 'package:app_flutter/widgets/task_icon.dart';

import '../utils/fake_flutter_build.dart';
import '../utils/mocks.dart';

void main() {
  group('StatusGrid', () {
    DevelopmentCocoonService service;

    List<CommitStatus> statuses;

    TaskMatrix taskMatrix;

    setUpAll(() async {
      service = DevelopmentCocoonService(DateTime(2020));
      final CocoonResponse<List<CommitStatus>> response = await service.fetchCommitStatuses();
      statuses = response.data;
      taskMatrix = TaskMatrix(statuses: statuses);
    });

    tearDown(() {
      // Image.Network caches images which must be cleared.
      PaintingBinding.instance.imageCache.clear();
    });

    testWidgets('shows loading indicator when statuses is empty', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ValueProvider<BuildState>(
            value: FakeBuildState(),
            child: const StatusGridContainer(),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(GridView), findsNothing);
    });

    testWidgets('commits show in the same column (indirectly via StatusGridContainer)', (WidgetTester tester) async {
      final BuildState buildState = BuildState(
        cocoonService: service,
        authService: MockGoogleSignInService(),
      );
      void listener1() {}
      buildState.addListener(listener1);

      await tester.pumpWidget(
        MaterialApp(
          home: ValueProvider<BuildState>(
            value: buildState,
            child: const StatusGridContainer(),
          ),
        ),
      );

      final List<Element> commits = find.byType(CommitBox).evaluate().toList();

      final double xPosition = commits.first.size.topLeft(Offset.zero).dx;

      for (final Element commit in commits) {
        // All the x positions should match the first instance if they're all in the same column
        expect(commit.size.topLeft(Offset.zero).dx, xPosition);
      }

      await tester.pumpWidget(Container());
      buildState.dispose();
    });

    testWidgets('commits show in the same column', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: StatusGrid(
            buildState: FakeBuildState(),
            statuses: statuses,
            taskMatrix: taskMatrix,
          ),
        ),
      );

      final List<Element> commits = find.byType(CommitBox).evaluate().toList();

      final double xPosition = commits.first.size.topLeft(Offset.zero).dx;

      for (final Element commit in commits) {
        // All the x positions should match the first instance if they're all in the same column
        expect(commit.size.topLeft(Offset.zero).dx, xPosition);
      }
    });

    testWidgets('first task in grid is the first task given', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: StatusGrid(
            buildState: FakeBuildState(),
            statuses: statuses,
            taskMatrix: taskMatrix,
          ),
        ),
      );

      final TaskBox firstTask = find.byType(TaskBox).evaluate().first.widget as TaskBox;
      expect(firstTask.task, taskMatrix.task(0, 0));
    });

    /// Matrix Diagram:
    /// ✓☐☐
    /// ☐✓☐
    /// ☐☐✓
    /// To construct the matrix from this diagram, each [CommitStatus] must have a unique [Task]
    /// that does not share its name with any other [Task]. This will make that [CommitStatus] have
    /// its task on its own unique row and column.
    final List<CommitStatus> statusesWithSkips = <CommitStatus>[
      CommitStatus()
        ..commit = (Commit()..author = 'Author')
        ..stages.add(Stage()
          ..name = 'A'
          ..tasks.addAll(<Task>[
            Task()
              ..name = '1'
              ..status = TaskBox.statusSucceeded
          ])),
      CommitStatus()
        ..commit = (Commit()..author = 'Author')
        ..stages.add(Stage()
          ..name = 'A'
          ..tasks.addAll(<Task>[
            Task()
              ..name = '2'
              ..status = TaskBox.statusSucceeded
          ])),
      CommitStatus()
        ..commit = (Commit()..author = 'Author')
        ..stages.add(Stage()
          ..name = 'A'
          ..tasks.addAll(<Task>[
            Task()
              ..name = '3'
              ..status = TaskBox.statusSucceeded
          ]))
    ];

    testWidgets('skipped tasks do not break the grid', (WidgetTester tester) async {
      final TaskMatrix taskMatrix = TaskMatrix(statuses: statusesWithSkips);

      await tester.pumpWidget(
        MaterialApp(
          home: StatusGrid(
            buildState: FakeBuildState(),
            statuses: statusesWithSkips,
            taskMatrix: taskMatrix,
            insertCellKeys: true,
          ),
        ),
      );

      expect(find.byType(TaskBox), findsNWidgets(3));

      // Row 1: ✓☐☐
      final TaskBox firstTask = find.byKey(const Key('cell-0-0')).evaluate().first.widget as TaskBox;
      expect(firstTask.task, statusesWithSkips[0].stages[0].tasks[0]);

      final SizedBox skippedTaskRow1Col2 = find.byKey(const Key('cell-0-1')).evaluate().first.widget as SizedBox;
      expect(skippedTaskRow1Col2, isNotNull);

      final SizedBox skippedTaskRow1Col3 = find.byKey(const Key('cell-0-2')).evaluate().first.widget as SizedBox;
      expect(skippedTaskRow1Col3, isNotNull);

      // Row 2: ☐✓☐
      final SizedBox skippedTaskRow2Col1 = find.byKey(const Key('cell-1-0')).evaluate().first.widget as SizedBox;
      expect(skippedTaskRow2Col1, isNotNull);

      final TaskBox secondTask = find.byKey(const Key('cell-1-1')).evaluate().first.widget as TaskBox;
      expect(secondTask.task, statusesWithSkips[1].stages[0].tasks[0]);

      final SizedBox skippedTaskRow2Col3 = find.byKey(const Key('cell-1-2')).evaluate().first.widget as SizedBox;
      expect(skippedTaskRow2Col3, isNotNull);

      // Row 3: ☐☐✓
      final SizedBox skippedTaskRow3Col1 = find.byKey(const Key('cell-2-0')).evaluate().first.widget as SizedBox;
      expect(skippedTaskRow3Col1, isNotNull);

      final SizedBox skippedTaskRow3Col2 = find.byKey(const Key('cell-2-1')).evaluate().first.widget as SizedBox;
      expect(skippedTaskRow3Col2, isNotNull);

      final TaskBox lastTask = find.byKey(const Key('cell-2-2')).evaluate().first.widget as TaskBox;
      expect(lastTask.task, statusesWithSkips[2].stages[0].tasks[0]);
    });

    testWidgets('all cells in the grid have the same size even when grid has skipped tasks',
        (WidgetTester tester) async {
      final TaskMatrix taskMatrix = TaskMatrix(statuses: statusesWithSkips);

      await tester.pumpWidget(
        MaterialApp(
          home: StatusGrid(
            buildState: FakeBuildState(),
            statuses: statusesWithSkips,
            taskMatrix: taskMatrix,
            insertCellKeys: true,
          ),
        ),
      );

      // Compare all the cells to the first cell to check they all have
      // the same size
      final Element taskBox = find.byKey(const Key('cell-0-0')).evaluate().first;
      for (int rowIndex = 0; rowIndex < taskMatrix.rows; rowIndex++) {
        for (int colIndex = 0; colIndex < taskMatrix.columns; colIndex++) {
          final Element cell = find.byKey(Key('cell-$rowIndex-$colIndex')).evaluate().first;

          expect(taskBox.size, cell.size);
        }
      }
    });

    testWidgets('task icon row is created', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: StatusGrid(
            buildState: FakeBuildState(),
            statuses: statuses,
            taskMatrix: taskMatrix,
            insertCellKeys: true,
          ),
        ),
      );

      final List<Element> taskIcons = find.byType(TaskIcon).evaluate().toList();
      final double yPosition = taskIcons.first.size.topLeft(Offset.zero).dy;

      // Ensure all task icons are in the same row
      for (final Element taskIcon in taskIcons) {
        // All y positions should match the first instance if in the same row
        expect(taskIcon.size.topLeft(Offset.zero).dy, yPosition);
      }

      for (int taskIndex = 0; taskIndex < taskMatrix.columns; taskIndex++) {
        // Task icon indexes are one off because of the gridIndex having to
        // account for the first column of commit boxes.
        expect(find.byKey(Key('taskicon-${taskIndex + 1}')), findsOneWidget);
      }
    });

    testWidgets('loader row is created', (WidgetTester tester) async {
      final CocoonResponse<List<CommitStatus>> response = await service.fetchCommitStatuses();
      final List<CommitStatus> smallRangeOfStatusesToShowLoader = response.data.getRange(0, 2).toList();
      final TaskMatrix smallTaskMatrix = TaskMatrix(statuses: smallRangeOfStatusesToShowLoader);
      await tester.pumpWidget(
        MaterialApp(
          home: StatusGrid(
            buildState: FakeBuildState(),
            statuses: smallRangeOfStatusesToShowLoader,
            taskMatrix: smallTaskMatrix,
            insertCellKeys: true,
          ),
        ),
      );

      /// Loader containers show 1 extra to account for the commit box
      /// column on the left of the grid.
      for (int index = 0; index < taskMatrix.columns + 1; index++) {
        expect(find.byKey(Key('loader-$index')), findsOneWidget);
      }
    });

    testWidgets('loader row is hidden when there are no more statuses', (WidgetTester tester) async {
      final CocoonResponse<List<CommitStatus>> response = await service.fetchCommitStatuses();
      final List<CommitStatus> smallRangeOfStatusesToShowLoader = response.data.getRange(0, 2).toList();
      final TaskMatrix smallTaskMatrix = TaskMatrix(statuses: smallRangeOfStatusesToShowLoader);
      await tester.pumpWidget(
        MaterialApp(
          home: StatusGrid(
            buildState: FakeBuildState()..moreStatusesExist = false,
            statuses: smallRangeOfStatusesToShowLoader,
            taskMatrix: smallTaskMatrix,
            insertCellKeys: true,
          ),
        ),
      );

      /// Loader containers show 1 extra to account for the commit box
      /// column on the left of the grid.
      for (int index = 0; index < taskMatrix.columns + 1; index++) {
        expect(find.byKey(Key('hidden-loader-$index')), findsOneWidget);
      }
    });
  });
}