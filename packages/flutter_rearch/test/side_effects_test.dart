import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_rearch/flutter_rearch.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rearch/rearch.dart';

import 'util.dart';

void main() {
  testWidgets('side effects transactions are done in 1 build', (tester) async {
    (int, void Function(int)) capsule1(CapsuleHandle use) => use.state(0);
    (int, void Function(int)) capsule2(CapsuleHandle use) => use.state(1);
    int buildCounterCapsule(CapsuleHandle use) {
      use(capsule1);
      use(capsule2);
      return use.isFirstBuild() ? 1 : (use(buildCounterCapsule) + 1);
    }

    final container = useContainer();

    var widgetBuildCount = 0;

    await tester.pumpWidget(
      CapsuleContainerProvider(
        container: container,
        child: RearchBuilder(
          builder: (context, use) {
            widgetBuildCount++;

            final (state1, setState1) = use(capsule1);
            final (state2, setState2) = use(capsule2);
            final (state3, setState3) = use.state(2);
            final (state4, setState4) = use.state(3);
            final runTransaction = use.transactionRunner();

            return MaterialApp(
              home: Column(
                children: [
                  for (final (i, value)
                      in [state1, state2, state3, state4].indexed)
                    Text('$i: $value'),
                  TextButton(
                    onPressed: () => runTransaction(() {
                      setState1(123);
                      setState2(123);
                      setState3(123);
                      setState4(123);
                    }),
                    child: const Text('click me'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );

    expect(widgetBuildCount, equals(1));
    expect(container.read(buildCounterCapsule), equals(1));
    expect(find.text('0: 0'), findsOneWidget);
    expect(find.text('1: 1'), findsOneWidget);
    expect(find.text('2: 2'), findsOneWidget);
    expect(find.text('3: 3'), findsOneWidget);

    await tester.tap(find.byType(TextButton));
    await tester.pump();

    expect(widgetBuildCount, equals(2));
    expect(container.read(buildCounterCapsule), equals(2));
    expect(find.text('0: 123'), findsOneWidget);
    expect(find.text('1: 123'), findsOneWidget);
    expect(find.text('2: 123'), findsOneWidget);
    expect(find.text('3: 123'), findsOneWidget);
  });

  testWidgets('a widget may update use.data during its build', (tester) async {
    ValueWrapper<int> rebuildableCapsule(CapsuleHandle use) => use.data(0);

    final container = useContainer();
    await tester.pumpWidget(
      MaterialApp(
        home: CapsuleContainerProvider(
          container: container,
          child: RearchBuilder(
            builder: (context, use) {
              use(rebuildableCapsule);
              final builds = ++use.data(0).value;
              return Text('$builds');
            },
          ),
        ),
      ),
    );
    expect(find.text('1'), findsOneWidget);
    container.read(rebuildableCapsule).value = 1;
    await tester.pump();
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets("future won't rebuild after build", (tester) async {
    final outerCompleter = Completer<void>();
    final innerCompleter = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: RearchBootstrapper(
          child: Scaffold(
            body: RearchBuilder(
              builder: (context, use) {
                final val = use.future(outerCompleter.future);
                if (val is AsyncLoading) {
                  return RearchBuilder(
                    builder: (context, use) {
                      use.future(innerCompleter.future);
                      return const CircularProgressIndicator();
                    },
                  );
                } else {
                  return const Text('switched');
                }
              },
            ),
          ),
        ),
      ),
    );
    expect(find.text('switched'), findsNothing);

    outerCompleter.complete(null);
    await tester.pump();
    expect(find.text('switched'), findsOneWidget);

    innerCompleter.complete(null);
    await tester.pump();
    expect(find.text('switched'), findsOneWidget);
  });

  testWidgets("stream won't rebuild after build", (tester) async {
    final outerCompleter = Completer<void>();
    final innerCompleter = Completer<void>();
    final outerStream = outerCompleter.future.asStream();
    final innerStream = innerCompleter.future.asStream();
    await tester.pumpWidget(
      MaterialApp(
        home: RearchBootstrapper(
          child: Scaffold(
            body: RearchBuilder(
              builder: (context, use) {
                final val = use.stream(outerStream);
                if (val is AsyncLoading) {
                  return RearchBuilder(
                    builder: (context, use) {
                      use.stream(innerStream);
                      return const CircularProgressIndicator();
                    },
                  );
                } else {
                  return const Text('switched');
                }
              },
            ),
          ),
        ),
      ),
    );
    expect(find.text('switched'), findsNothing);

    outerCompleter.complete(null);
    await tester.pump();
    expect(find.text('switched'), findsOneWidget);

    innerCompleter.complete(null);
    await tester.pump();
    expect(find.text('switched'), findsOneWidget);
  });

  testWidgets('PageView control test (default args)', (tester) async {
    final container = useContainer();

    const pages = <String>[
      'Page 1',
      'Page 2',
      'Page 3',
    ];

    final log = <String>[];

    await tester.pumpWidget(
      CapsuleContainerProvider(
        container: container,
        child: RearchBuilder(
          builder: (context, use) {
            final controller = use.pageController();

            return MaterialApp(
              home: Directionality(
                textDirection: TextDirection.ltr,
                child: PageView(
                  controller: controller,
                  dragStartBehavior: DragStartBehavior.down,
                  children: pages.map<Widget>((String page) {
                    return GestureDetector(
                      dragStartBehavior: DragStartBehavior.down,
                      onTap: () {
                        log.add(page);
                      },
                      child: Container(
                        height: 200,
                        color: const Color(0xFF0000FF),
                        child: Text(page),
                      ),
                    );
                  }).toList(),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Page 1'));
    expect(log, equals(<String>['Page 1']));
    log.clear();

    expect(find.text('Page 2'), findsNothing);

    await tester.drag(find.byType(PageView), const Offset(-20, 0));
    await tester.pump();

    expect(find.text('Page 1'), findsOneWidget);
    expect(find.text('Page 2'), findsOneWidget);
    expect(find.text('Page 3'), findsNothing);

    await tester.pumpAndSettle();

    expect(find.text('Page 1'), findsOneWidget);
    expect(find.text('Page 2'), findsNothing);

    await tester.drag(find.byType(PageView), const Offset(-401, 0));
    await tester.pumpAndSettle();

    expect(find.text('Page 1'), findsNothing);
    expect(find.text('Page 2'), findsOneWidget);
    expect(find.text('Page 3'), findsNothing);

    await tester.tap(find.text('Page 2'));
    expect(log, equals(<String>['Page 2']));
    log.clear();

    await tester.fling(find.byType(PageView), const Offset(-200, 0), 1000);
    await tester.pumpAndSettle();

    expect(find.text('Page 1'), findsNothing);
    expect(find.text('Page 2'), findsNothing);
    expect(find.text('Page 3'), findsOneWidget);

    await tester.fling(find.byType(PageView), const Offset(200, 0), 1000);
    await tester.pumpAndSettle();

    expect(find.text('Page 1'), findsNothing);
    expect(find.text('Page 2'), findsOneWidget);
    expect(find.text('Page 3'), findsNothing);
  });

  testWidgets('PageView control test (custom args)', (tester) async {
    final container = useContainer();

    const pages = <String>[
      'Page 1',
      'Page 2',
      'Page 3',
    ];

    final log = <String>[];
    var onAttachFired = false;

    await tester.pumpWidget(
      CapsuleContainerProvider(
        container: container,
        child: RearchBuilder(
          builder: (context, use) {
            final controller = use.pageController(
              initialPage: 1,
              viewportFraction: 0.5,
              onAttach: (_) => onAttachFired = true,
            );

            return MaterialApp(
              home: Directionality(
                textDirection: TextDirection.ltr,
                child: PageView(
                  controller: controller,
                  dragStartBehavior: DragStartBehavior.down,
                  children: pages.map<Widget>((String page) {
                    return GestureDetector(
                      dragStartBehavior: DragStartBehavior.down,
                      onTap: () {
                        log.add(page);
                      },
                      child: Container(
                        height: 200,
                        color: const Color(0xFF0000FF),
                        child: Text(page),
                      ),
                    );
                  }).toList(),
                ),
              ),
            );
          },
        ),
      ),
    );

    expect(onAttachFired, isTrue);

    await tester.tap(find.text('Page 1'));
    expect(log, equals(<String>['Page 1']));
    log.clear();

    expect(find.text('Page 2'), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(-20, 0));
    await tester.pump();

    expect(find.text('Page 1'), findsOneWidget);
    expect(find.text('Page 2'), findsOneWidget);
    expect(find.text('Page 3'), findsOneWidget);

    await tester.pumpAndSettle();

    expect(find.text('Page 1'), findsOneWidget);
    expect(find.text('Page 2'), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(-401, 0));
    await tester.pumpAndSettle();

    expect(find.text('Page 1'), findsNothing);
    expect(find.text('Page 2'), findsOneWidget);
    expect(find.text('Page 3'), findsOneWidget);

    await tester.tap(find.text('Page 2'));
    expect(log, equals(<String>['Page 2']));
    log.clear();

    await tester.fling(find.byType(PageView), const Offset(-200, 0), 1000);
    await tester.pumpAndSettle();

    expect(find.text('Page 1'), findsNothing);
    expect(find.text('Page 2'), findsOneWidget);
    expect(find.text('Page 3'), findsOneWidget);

    await tester.fling(find.byType(PageView), const Offset(601, 0), 1000);
    await tester.pumpAndSettle();

    expect(find.text('Page 1'), findsOneWidget);
    expect(find.text('Page 2'), findsOneWidget);
    expect(find.text('Page 3'), findsNothing);

    await tester.pumpAndSettle();
  });

  testWidgets('automatic keep alive can be deactivated (#199)', (tester) async {
    await tester.pumpWidget(
      RearchBootstrapper(
        child: MaterialApp(
          home: RearchBuilder(
            builder: (context, use) {
              final switchedPage = use.data(false);

              if (switchedPage.value) {
                return const Text('No assert!');
              }

              return CustomScrollView(
                slivers: [
                  SliverList.list(
                    children: List.generate(50, (index) {
                      return RearchBuilder(
                        builder: (context, use) {
                          use.automaticKeepAlive();
                          return SizedBox(
                            width: 600,
                            height: 200,
                            child: TextButton(
                              onPressed: () => switchedPage.value = true,
                              child: Text('switch $index'),
                            ),
                          );
                        },
                      );
                    }),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('switch 0'));
    await tester.pump();

    expect(find.text('No assert!'), findsOneWidget);
  });

  testWidgets('detached widgets are not rebuilt by side effects (#304)',
      (tester) async {
    ValueWrapper<int> rebuildableCapsule(CapsuleHandle use) => use.data(0);
    ValueWrapper<bool> displayToggleCapsule(CapsuleHandle use) =>
        use.data(true);

    final container = useContainer();
    await tester.pumpWidget(
      MaterialApp(
        home: CapsuleContainerProvider(
          container: container,
          child: RearchBuilder(builder: (context, use) {
            final displayTestWidget = use(displayToggleCapsule);
            final builds = ++use.data(0).value;

            return Column(
              children: [
                displayTestWidget.value
                    ? Container(
                        child: RearchBuilder(
                          builder: (context, use) {
                            use(rebuildableCapsule);
                            final builds = ++use.data(0).value;
                            return Text('inner $builds');
                          },
                        ),
                      )
                    : Container(
                        child: Text('replacement widget $builds'),
                      ),
                Container(
                  child: Text('outer $builds'),
                )
              ],
            );
          }),
        ),
      ),
    );
    expect(find.text('outer 1'), findsOneWidget);
    expect(find.text('inner 1'), findsOneWidget);
    container.read(displayToggleCapsule).value = false;
    await tester.pump();
    expect(find.text('replacement widget 2'), findsOneWidget);
    expect(find.text('outer 2'), findsOneWidget);

    // Forcing a delay causes the test to run forever
    // await Future.delayed(Durations.long4);

    container.read(rebuildableCapsule).value = 1;
    await tester.pump();

    //TODO: Also expect the lack of a specific exception? Or maybe just this
    // test that the build numbers didn't increment and the test completes is
    // enough.
    expect(find.text('replacement widget 2'), findsOneWidget);
    expect(find.text('outer 2'), findsOneWidget);
  });
}
