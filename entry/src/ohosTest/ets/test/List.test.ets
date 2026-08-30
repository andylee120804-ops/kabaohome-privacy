/**
 * 卡宝Home 单元测试入口
 * 在 DevEco Studio 中右键 → Run 'ohosTest' 即可运行
 */
import utilsTest from './Utils.test';
import constantsTest from './Constants.test';
import modelTest from './Model.test';
import periodViewModelTest from './PeriodViewModel.test';
import healthViewModelTest from './HealthViewModel.test';
import kidsViewModelTest from './KidsViewModel.test';

export default function testsuite() {
  utilsTest();
  constantsTest();
  modelTest();
  periodViewModelTest();
  healthViewModelTest();
  kidsViewModelTest();
}
