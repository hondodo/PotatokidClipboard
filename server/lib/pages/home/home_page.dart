import 'package:app_translator_web/components/user_login_widget.dart';
import 'package:app_translator_web/framework/base/base_stateless_underline_bar_widget.dart';
import 'package:app_translator_web/pages/home/vm/home_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class HomePage extends BaseStatelessUnderlineBarWidget<HomeController> {
  const HomePage({super.key})
      : super(
            barBackgroundColor: Colors.blue, barForegroundColor: Colors.white);

  @override
  String getTitle() {
    return '薯仔工具箱';
  }

  @override
  List<Widget>? buildActions() {
    return const [
      Padding(
        padding: EdgeInsets.only(right: 16.0),
        child: UserLoginWidget(),
      ),
    ];
  }

  @override
  Widget buildBody(BuildContext context) {
    return CustomScrollView(
      slivers: [
        const SliverToBoxAdapter(
          child: SizedBox(
            height: 16,
          ),
        ),
        SliverList.separated(
            itemBuilder: (context, index) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildFeatureCard(
                      context: context,
                      title: controller.featureCards[index].title,
                      description: controller.featureCards[index].description,
                      icon: controller.featureCards[index].icon,
                      color: controller.featureCards[index].color,
                      route: controller.featureCards[index].route),
                ),
            separatorBuilder: (context, index) => const SizedBox(height: 16),
            itemCount: controller.featureCards.length),
        SliverPadding(
          padding: const EdgeInsets.all(16.0),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              // // 功能卡片
              // _buildFeatureCard(
              //   context: context,
              //   title: '上传文件',
              //   description: '选择并上传文件到服务器',
              //   icon: Icons.cloud_upload,
              //   color: Colors.blue,
              //   route: RouterNames.upload,
              // ),
              // const SizedBox(height: 16),
              // _buildFeatureCard(
              //   context: context,
              //   title: '文件管理',
              //   description: '查看、管理和删除已上传的文件',
              //   icon: Icons.folder,
              //   color: Colors.green,
              //   route: RouterNames.files,
              // ),
              // const SizedBox(height: 16),
              // _buildFeatureCard(
              //   context: context,
              //   title: '笔记管理',
              //   description: '创建、查看和管理个人笔记',
              //   icon: Icons.note,
              //   color: Colors.purple,
              //   route: RouterNames.notes,
              // ),
              // const SizedBox(height: 16),
              // _buildFeatureCard(
              //   context: context,
              //   title: '翻译上传',
              //   description: '上传和管理App翻译文件',
              //   icon: Icons.translate,
              //   color: Colors.orange,
              //   route: RouterNames.uploadTranslation,
              // ),
              // const SizedBox(height: 16),
              // _buildFeatureCard(
              //   context: context,
              //   title: '翻译修改',
              //   description: '编辑和管理已上传的翻译内容',
              //   icon: Icons.edit,
              //   color: Colors.teal,
              //   route: RouterNames.modifyTranslation,
              // ),
              // // const SizedBox(height: 16),
              // // _buildFeatureCard(
              // //   context: context,
              // //   title: '天气',
              // //   description: '查看天气信息',
              // //   icon: Icons.cloud,
              // //   color: Colors.red,
              // //   route: RouterNames.weather,
              // // ),
              // const SizedBox(height: 32),

              // 使用说明
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.info, color: Colors.blue),
                          SizedBox(width: 8),
                          Text(
                            '使用说明',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        '1. 点击"上传文件"按钮可以上传新文件到服务器（最大600MB）\n'
                        '2. 点击"文件管理"按钮可以查看和管理已上传的文件\n'
                        '3. 点击"笔记管理"按钮可以创建和管理个人笔记\n'
                        '4. 点击"翻译上传"按钮可以上传App翻译文件（.json格式）\n'
                        '5. 点击"翻译修改"按钮可以编辑和管理已上传的翻译内容\n'
                        '6. 支持多种文件格式：文档、图片、视频、音频等\n'
                        '7. 笔记按用户名分类，只有输入正确用户名才能查看',
                        style: TextStyle(fontSize: 14, height: 1.5),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.lightbulb, color: Colors.orange),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '提示：确保服务器正在运行，否则无法上传或查看文件。',
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _buildFeatureCard({
    required BuildContext context,
    required String title,
    required String description,
    required IconData icon,
    required Color color,
    required String route,
  }) {
    return Card(
      elevation: 4,
      child: InkWell(
        onTap: () {
          // Navigator.pushNamed(context, route);
          Get.toNamed(route);
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(24.0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [color.withOpacity(0.1), color.withOpacity(0.05)],
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 32,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                color: color,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
