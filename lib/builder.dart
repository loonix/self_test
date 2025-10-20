import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';
import 'src/self_test_generator.dart';

Builder selfTestBuilder(BuilderOptions options) => LibraryBuilder(SelfTestGenerator());
