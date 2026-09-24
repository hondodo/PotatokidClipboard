import 'package:app_translator_web/framework/base/base_get_vm.dart';
import 'package:app_translator_web/pages/home/model/feature_card_model.dart';
import 'package:app_translator_web/routes/router_names.dart';
import 'package:flutter/material.dart';
import 'package:get/get_rx/src/rx_types/rx_types.dart';

class HomeController extends BaseGetVM {
  RxList<FeatureCardModel> featureCards = RxList<FeatureCardModel>([]);

  @override
  void onInit() {
    super.onInit();
    initFeatureCards();
  }

  void addFeatureCard(FeatureCardModel featureCard) {
    featureCards.add(featureCard);
  }

  void initFeatureCards() {
    addFeatureCard(FeatureCardModel(
      title: '上传文件',
      description: '选择并上传文件到服务器',
      icon: Icons.cloud_upload,
      color: Colors.blue,
      route: RouterNames.upload,
    ));
    addFeatureCard(FeatureCardModel(
      title: '文件管理',
      description: '查看、管理和删除已上传的文件',
      icon: Icons.folder,
      color: Colors.green,
      route: RouterNames.files,
    ));
    addFeatureCard(FeatureCardModel(
      title: '笔记管理',
      description: '创建、查看和管理个人笔记',
      icon: Icons.note,
      color: Colors.purple,
      route: RouterNames.notes,
    ));
    addFeatureCard(FeatureCardModel(
      title: '翻译上传',
      description: '上传和管理App翻译文件',
      icon: Icons.translate,
      color: Colors.orange,
      route: RouterNames.uploadTranslation,
    ));
    addFeatureCard(FeatureCardModel(
      title: '翻译修改',
      description: '编辑和管理已上传的翻译内容',
      icon: Icons.edit,
      color: Colors.teal,
      route: RouterNames.modifyTranslation,
    ));
  }
}
