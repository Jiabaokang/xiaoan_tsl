# ML Kit 通过清单中的类名反射创建组件注册器，Release 压缩时须保留其无参构造。
-keep class com.google.mlkit.**Registrar { public <init>(); }
