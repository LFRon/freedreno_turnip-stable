### 这玩意是什么?
这是将Mesa3D稳定版本分支的骁龙开源图形驱动Freedreno中的Turnip的Vulkan驱动构建成Magisk/KernelSU模块的构建中心,由ilhan-athn7大佬跟随main上游的构建脚本修改而成
本脚本为了稳定性而跟随Mesa3D的稳定版分支而非上游main分支

### Scheduled Releases
- Mesa3D上游啥时候更新了下一个稳定分支,而我没开Action的话记得开Issue催我,一般情况下我会改

### Notes;

#### Magisk build:
- Root must be visible to target app/game.
- Tested with these apps/games listed [here](list.md).

#### Adreno Tools build: (这玩意我不知道干嘛用的,我改脚本时没有怎么在意它,跑出来是个空包)
- Follow application specific instructions to install the driver package.

### To Build Locally (如何在本地进行模块构建)
- Obtain the script [turnip_builder.sh](https://raw.githubusercontent.com/ilhan-athn7/freedreno_turnip-CI/main/turnip_builder.sh) on your linux environment. (visit the link and use ```CTRL + S``` keys)
- Execute script on linux terminal ```bash ./turnip_builder.sh```
- To build experimental branchs, change [this](https://github.com/ilhan-athn7/freedreno_turnip-CI/blob/6ef9860e7b755b8b7a83e4ecd398b355a56f9d49/turnip_builder.sh#L11) line, and add one more line to rename unzipped folder to mesa-main.

### References

- https://forum.xda-developers.com/t/getting-freedreno-turnip-mesa-vulkan-driver-on-a-poco-f3.4323871/

- https://gitlab.freedesktop.org/mesa/mesa/-/issues/6802

- https://github.com/bylaws/libadrenotools
