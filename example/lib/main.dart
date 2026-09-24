import "dart:async";
import "dart:io";
import "dart:typed_data";

import "package:flutter/material.dart";
import "package:flutter/services.dart" show rootBundle;
import "package:flutter_lynx/flutter_lynx.dart";

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LynxLogger.onLog = (tag, msg, {error}) {
    _addLog("[$tag] $msg${error != null ? ' ($error)' : ''}");
  };
  _initLynxHostCapabilities();
  runApp(const LynxDemoApp());
}

final List<String> _bridgeLogs = [];
final StreamController<List<String>> _logStreamController =
    StreamController<List<String>>.broadcast();

void _addLog(String msg) {
  final timestamp = DateTime.now().toIso8601String().substring(11, 19);
  _bridgeLogs.insert(0, "[$timestamp] $msg");
  if (_bridgeLogs.length > 50) _bridgeLogs.removeLast();
  _logStreamController.add(List.from(_bridgeLogs));
}

/// Initialize host capabilities and register with Lynx JSBridge
void _initLynxHostCapabilities() {
  final bridge = LynxBridge.instance;

  // 1. User & Auth info
  bridge.register("getUserInfo", (params) async {
    _addLog("JSB >> getUserInfo called");
    return {
      "userId": "U_889901",
      "userName": "张店长 (Manager)",
      "phone": "13812345678",
      "token": "bearer_jwt_token_demo_2026",
      "roles": ["store_manager", "cashier"],
      "merchantName": "Koklam 旗舰店",
    };
  }, module: "user");

  // 2. QR Code scanner
  bridge.register("scanQRCode", (params) async {
    _addLog("JSB >> scanQRCode invoked by Lynx mini program");
    return {
      "code": "https://kmanager.example.com/desk/A08?shop=SHOP_01",
      "format": "QR_CODE",
    };
  }, module: "scanner");

  // 3. HTTP Network Request Proxy
  bridge.register("request", (params) async {
    final url = params["url"]?.toString() ?? "";
    final method = params["method"]?.toString() ?? "GET";
    _addLog("JSB >> request proxy: $method $url");
    return {
      "statusCode": 200,
      "statusMessage": "OK",
      "data": {
        "desks": [
          {
            "id": "A01",
            "name": "大厅A01 (4人)",
            "status": "occupied",
            "amount": 258.0
          },
          {"id": "A02", "name": "大厅A02 (6人)", "status": "idle", "amount": 0.0},
          {
            "id": "B01",
            "name": "包厢B01 (10人)",
            "status": "reserved",
            "amount": 888.0
          },
        ],
      },
    };
  }, module: "network");

  // 4. Report Exporter & Analytics
  bridge.register("exportReport", (params) async {
    final range = params["range"]?.toString() ?? "today";
    final format = params["format"]?.toString() ?? "xlsx";
    _addLog("JSB >> exportReport 导出报表: range=$range, format=$format");
    await Future.delayed(const Duration(milliseconds: 300));
    return {
      "fileName":
          "KManager_经营日报_${DateTime.now().millisecondsSinceEpoch}.$format",
      "fileSize": "142.8 KB",
      "recordsCount": 328,
      "totalRevenue": 28450.00,
      "downloadUrl":
          "https://kmanager.example.com/reports/download/rep_889901.xlsx",
      "exportedAt": DateTime.now().toIso8601String(),
    };
  }, module: "report");

  // 5. Custom UI Handler
  bridge.uiHandler.onShowToast = (title, {icon, durationMs}) {
    _addLog("JSB >> showToast: $title (icon: $icon)");
  };
}

class LynxDemoApp extends StatelessWidget {
  const LynxDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Lynx Dynamic Mini-Program Demo",
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1677FF)),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1677FF),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const DemoHomePage(),
    );
  }
}

class DemoHomePage extends StatefulWidget {
  const DemoHomePage({super.key});

  @override
  State<DemoHomePage> createState() => _DemoHomePageState();
}

class _DemoHomePageState extends State<DemoHomePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _customUrlController = TextEditingController(
    text:
        "https://raw.githubusercontent.com/lynx-family/lynx/main/examples/hello-world/dist/main.lynx.bundle",
  );

  LynxController? _embeddedLynxController;
  LynxController? _inlineCardController;
  int _counter = 0;

  /// 内置真实 tasm 二进制模板产物（运行时 A 验证包，engineVersion 4.1），
  /// 演示 templateBytes 直喂：内容随 App 版本内置，不经文件与缓存链路。
  static const String _inlineCardAsset = "assets/miniapp/runtime-a.lynx.bundle";
  Uint8List? _inlineCardBytes;

  Future<void> _loadEmbeddedCardViaBytes() async {
    final bytes = await rootBundle.load(_inlineCardAsset);
    final templateBytes = bytes.buffer
        .asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
    _addLog(
        "Host >> 直喂内置产物 ${templateBytes.length} 字节（与文件链路同源内容）");
    setState(() => _inlineCardBytes = templateBytes);
  }

  Future<void> _loadEmbeddedCardViaFileBaseline() async {
    // 对照组：同一份产物先落盘，再走既有文件链路，验证两条链路渲染一致。
    final bytes = await rootBundle.load(_inlineCardAsset);
    final tempFile = File(
        "${Directory.systemTemp.path}/inline-card-parity.lynx.bundle");
    await tempFile.writeAsBytes(bytes.buffer
        .asUint8List(bytes.offsetInBytes, bytes.lengthInBytes));
    _addLog("Host >> 文件链路对照加载: ${tempFile.path}");
    setState(() => _inlineCardBytes = null);
    _fileBaselinePath = tempFile.path;
  }

  String? _fileBaselinePath;

  final List<MiniProgramManifest> _presetMiniPrograms = [
    const MiniProgramManifest(
      appId: "kmanager_report_miniapp",
      name: "📊 门店经营分析与多维报表",
      version: "3.0.0",
      bundleUrl:
          "https://cdn.example.com/miniapp/report/3.0.0/main.lynx.bundle",
      description: "实时分时营收柱状趋势图、品类环形占比、Top 热销排行榜与导出 Excel 宿主协同。",
      initialData: {"storeId": "STORE_001", "period": "today"},
    ),
    const MiniProgramManifest(
      appId: "kmanager_local_demo",
      name: "📦 本地内置小程序 (离线秒开)",
      version: "1.0.0",
      bundleUrl: "assets/miniapp/main.lynx.bundle",
      description: "内置预打包的 Lynx 示例小程序，免网络直接秒开，支持实时 JSB 交互调试。",
      initialData: {"theme": "light", "user": "管理员", "role": "admin"},
    ),
    const MiniProgramManifest(
      appId: "kmanager_desk_miniapp",
      name: "桌台管理与巡检小程序",
      version: "1.0.2",
      bundleUrl: "https://cdn.example.com/miniapp/desk/1.0.2/main.lynx.bundle",
      description: "用于现场实时查看桌台占用状态、开台点单与巡检确认（演示远程 Bundle 回退机制）。",
      initialData: {"theme": "light", "shopId": "SHOP_001"},
    ),
    const MiniProgramManifest(
      appId: "kmanager_order_miniapp",
      name: "扫码动态点餐小程序",
      version: "2.1.0",
      bundleUrl: "https://cdn.example.com/miniapp/order/2.1.0/main.lynx.bundle",
      description: "顾客与员工快捷点单，支持呼叫服务与加菜提醒。",
      initialData: {"deskNo": "A08", "currency": "CNY"},
    ),
    const MiniProgramManifest(
      appId: "kmanager_member_miniapp",
      name: "会员卡包与积分商城",
      version: "1.5.0",
      bundleUrl:
          "https://cdn.example.com/miniapp/member/1.5.0/main.lynx.bundle",
      description: "动态会员权益展示、优惠券核销与积分兑换。",
      initialData: {"memberLevel": "VIP_GOLD"},
    ),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _addLog("Host system initialized. LynxBridge ready.");
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_presetMiniPrograms.isNotEmpty && mounted) {
        _launchMiniProgram(_presetMiniPrograms.first);
      }
    });
  }

  void _launchMiniProgram(MiniProgramManifest manifest) {
    _addLog(
        "Launching Mini-Program: ${manifest.name} (appId: ${manifest.appId})");
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => LynxMiniProgramPage(manifest: manifest),
      ),
    );
  }

  void _launchCustomMiniProgram() {
    final url = _customUrlController.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("请输入有效的 Bundle URL")),
      );
      return;
    }

    final manifest = MiniProgramManifest(
      appId: "custom_miniapp_${DateTime.now().millisecondsSinceEpoch}",
      name: "自定义动态小程序",
      version: "1.0.0",
      bundleUrl: url,
      description: "开发者自定义加载的 Lynx 小程序",
    );

    _launchMiniProgram(manifest);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.bolt, color: Colors.amber),
            SizedBox(width: 8),
            Text(
              "Lynx 动态小程序 Demo",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.apps), text: "小程序中心"),
            Tab(icon: Icon(Icons.view_quilt), text: "组件嵌入"),
            Tab(icon: Icon(Icons.terminal), text: "JSB 调测日志"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildMiniProgramLauncherTab(),
          _buildEmbeddedViewTab(),
          _buildBridgeLogTab(),
        ],
      ),
    );
  }

  // --- Tab 1: Mini Program Launcher ---
  Widget _buildMiniProgramLauncherTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Top Banner
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1677FF), Color(0xFF36CFC9)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Lynx 跨端动态小程序容器",
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 6),
              Text(
                "基于 https://lynxjs.org/ 引擎，支持动态热更、离线秒开与双向 JSBridge 通信。",
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Presets list
        const Text(
          "预设动态业务小程序",
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        ..._presetMiniPrograms.map((manifest) {
          return Card(
            elevation: 1,
            margin: const EdgeInsets.only(bottom: 12),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.mobile_friendly,
                            color: Color(0xFF1677FF)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              manifest.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                            Text(
                              "AppId: ${manifest.appId} • v${manifest.version}",
                              style: TextStyle(
                                  color: Colors.grey.shade600, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton(
                        onPressed: () => _launchMiniProgram(manifest),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1677FF),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text("打开"),
                      ),
                    ],
                  ),
                  if (manifest.description != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      manifest.description!,
                      style:
                          TextStyle(color: Colors.grey.shade700, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
          );
        }),

        const Divider(height: 32),

        // Custom Bundle URL Launcher
        const Text(
          "自定义远程 / 本地 Bundle 启动",
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _customUrlController,
          decoration: InputDecoration(
            labelText: "Bundle URL (支持 http://, https://, file://, assets://)",
            hintText: "http://127.0.0.1:3000/main.lynx.bundle",
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            prefixIcon: const Icon(Icons.link),
          ),
          style: const TextStyle(fontSize: 13),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            ActionChip(
              avatar: const Icon(Icons.flash_on, size: 16, color: Colors.amber),
              label: const Text("本地 DevServer (127.0.0.1:3000)",
                  style: TextStyle(fontSize: 11)),
              onPressed: () {
                _customUrlController.text =
                    "http://127.0.0.1:3000/main.lynx.bundle";
              },
            ),
            ActionChip(
              avatar:
                  const Icon(Icons.folder_zip, size: 16, color: Colors.blue),
              label: const Text("内置离线 Bundle", style: TextStyle(fontSize: 11)),
              onPressed: () {
                _customUrlController.text = "assets/miniapp/main.lynx.bundle";
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: _launchCustomMiniProgram,
          icon: const Icon(Icons.play_arrow),
          label: const Text("启动自定义小程序"),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(46),
            backgroundColor: Colors.teal,
            foregroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ],
    );
  }

  // --- Tab 2: Embedded View Tab ---
  Widget _buildEmbeddedViewTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          "嵌入式 LynxView 组件测试",
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Text(
          "通过 PlatformView 直接在原生页面内嵌入动态卡片，支持实时双向数据同步。",
          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
        ),
        const SizedBox(height: 16),

        // Lynx View Container
        Container(
          height: 240,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.antiAlias,
          child: LynxView(
            url: "https://cdn.example.com/cards/stats_card.lynx.bundle",
            initialData: LynxTemplateData({
              "title": "今日经营数据",
              "count": _counter,
              "store": "旗舰总店",
            }),
            onLynxCreated: (controller) {
              _embeddedLynxController = controller;
              _addLog("Embedded LynxView created.");
            },
            onLoadSuccess: () {
              _addLog("Embedded LynxView loaded successfully.");
            },
            onLoadFail: (error) {
              _addLog("Embedded LynxView load error: $error");
            },
          ),
        ),
        const SizedBox(height: 16),

        // Controls
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  setState(() => _counter++);
                  _embeddedLynxController?.updateData({
                    "count": _counter,
                    "updatedAt": DateTime.now().toIso8601String(),
                  });
                  _inlineCardController?.updateData({"count": _counter});
                  _addLog("Host >> updateData(count: $_counter)");
                },
                icon: const Icon(Icons.add),
                label: Text("更新数据 ($_counter)"),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  _embeddedLynxController?.sendCustomEvent("flutterPing", {
                    "timestamp": DateTime.now().millisecondsSinceEpoch,
                  });
                  _addLog("Host >> sendCustomEvent(flutterPing)");
                },
                icon: const Icon(Icons.send),
                label: const Text("发送自定义事件"),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () {
            _embeddedLynxController?.reload();
            _addLog("Host >> reload() called on LynxView");
          },
          icon: const Icon(Icons.refresh),
          label: const Text("重载 LynxView 组件"),
          style:
              OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(40)),
        ),

        const SizedBox(height: 24),
        const Text(
          "直喂模板源码加载（对齐官方 loadTemplate）",
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        const Text(
          "确认卡片模板产物随 App 版本内置，运行时经 loadFromSource/templateBytes 直喂引擎，"
          "不再要求先落盘；下方两个入口喂入同一份内置产物，可对照渲染结果。",
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _loadEmbeddedCardViaFileBaseline,
                icon: const Icon(Icons.description_outlined, size: 18),
                label: const Text("文件链路 (对照)",
                    style: TextStyle(fontSize: 12)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _loadEmbeddedCardViaBytes,
                icon: const Icon(Icons.bolt, size: 18),
                label: const Text("直喂产物 bytes", style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1677FF),
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          height: 240,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.antiAlias,
          child: _buildInlineCardBody(),
        ),
      ],
    );
  }

  Widget _buildInlineCardBody() {
    if (_inlineCardBytes != null) {
      return LynxView(
        key: const ValueKey("inline-bytes"),
        templateBytes: _inlineCardBytes,
        initialData: const LynxTemplateData({
          "title": "直喂确认卡片",
          "source": "templateBytes",
        }),
        onLynxCreated: (controller) {
          _inlineCardController = controller;
          _addLog("Inline LynxView created (templateBytes 模式).");
        },
        onLoadSuccess: () =>
            _addLog("Inline LynxView loaded (直喂链路首屏成功)."),
        onLoadFail: (error) => _addLog("Inline LynxView load error: $error"),
      );
    }
    if (_fileBaselinePath != null) {
      return LynxView(
        key: const ValueKey("inline-file"),
        url: _fileBaselinePath,
        initialData: const LynxTemplateData({
          "title": "直喂确认卡片",
          "source": "url",
        }),
        onLynxCreated: (controller) {
          _inlineCardController = controller;
          _addLog("Inline LynxView created (url 文件对照模式).");
        },
        onLoadSuccess: () =>
            _addLog("Inline LynxView loaded (文件链路对照首屏成功)."),
        onLoadFail: (error) => _addLog("Inline LynxView load error: $error"),
      );
    }
    return Center(
      child: Text(
        "选择上方入口加载内置确认卡片模板",
        style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
      ),
    );
  }

  // --- Tab 3: JSBridge Logs ---
  Widget _buildBridgeLogTab() {
    return Column(
      children: [
        // Action Bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "实时 JSBridge 交互日志",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () {
                      LynxBridge.instance.dispatch({
                        "callId":
                            "test_${DateTime.now().millisecondsSinceEpoch}",
                        "module": "scanner",
                        "method": "scanQRCode",
                        "params": {},
                      });
                    },
                    icon: const Icon(Icons.qr_code, size: 16),
                    label: const Text("测试扫码"),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: "清空日志",
                    onPressed: () {
                      _bridgeLogs.clear();
                      _logStreamController.add([]);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // Log Console List
        Expanded(
          child: StreamBuilder<List<String>>(
            stream: _logStreamController.stream,
            initialData: _bridgeLogs,
            builder: (context, snapshot) {
              final logs = snapshot.data ?? [];
              if (logs.isEmpty) {
                return const Center(
                  child: Text(
                    "暂无 JSB 交互记录",
                    style: TextStyle(color: Colors.grey),
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: logs.length,
                itemBuilder: (context, index) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E1E),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      logs[index],
                      style: const TextStyle(
                        fontFamily: "monospace",
                        fontSize: 12,
                        color: Color(0xFF4AF626),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _customUrlController.dispose();
    super.dispose();
  }
}
