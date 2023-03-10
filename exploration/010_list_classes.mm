#import <objc/runtime.h>
#include <iostream>
#include <iomanip>
#include <chrono>
#include <vector>

using namespace std;
using namespace std::chrono;

int main(int argc, const char * argv[]) {
    auto numClasses = objc_getClassList(nullptr, 0);
    Class * classes = static_cast<Class *>(malloc(sizeof(Class) * numClasses));

    numClasses = objc_getClassList(classes, numClasses);

    auto names = vector<const char *>(numClasses);

    for (int i = 0; i < numClasses; ++i) {
        Class cls = classes[i];
        const char *name = class_getName(cls);
        cout << setw(40) << name << ": " << class_getImageName(cls) << endl;
        names.push_back(name);
    }
    free(classes);

    cout << "Number of classes: " << numClasses << endl;
    Class cls;
    //lookup classes by name
    auto start = high_resolution_clock::now();
    for (auto name : names) {
        cls = objc_getClass(name);
    }
    auto fin = high_resolution_clock::now();
    cout << "Lookup by name: " << duration_cast<microseconds>(fin-start).count() << "us total, "
         << duration_cast<nanoseconds>((fin-start)/numClasses).count() << "ns per class" << endl;

    return 0;

}