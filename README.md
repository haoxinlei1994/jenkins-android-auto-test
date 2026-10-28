## 前提条件

安装docker并运行中，手机USB连接并打开调试，调用adb devices命令可以看到手机

## 使用步骤

1、先fork项目，然后clone到本地
2、修改monkey_test.sh脚本中的包名app_package、monkey测试的命令代码，然后提交到自己fork后的仓库
3、执行start.sh启动jenkins服务，过程中需要下载插件，需要等几分钟，启动成功后会在命令行输出用户名和密码
4、浏览器打开http://localhost:8080/,输入用户名和密码进入jenkins服务后台
6、新建Build选择Pipeline模式，选择Pipeline script from SCM，仓库地址填写自己fork的仓库，一定要取消勾选Lightweight checkout，保存
7、点击Build开始跑任务
