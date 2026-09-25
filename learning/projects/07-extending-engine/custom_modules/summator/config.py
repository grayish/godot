# 모듈 감지 조건: config.py + SCsub + register_types.cpp (methods.py is_module()).
# SConstruct 가 각 모듈의 can_build() 를 물어 True 인 것만 빌드에 포함한다.


def can_build(env, platform):
    return True


def configure(env):
    pass


# doc/tools/make_rst.py 와 --doctool 이 이 목록을 보고 doc_classes/<Class>.xml 을 찾는다.
def get_doc_classes():
    return [
        "Summator",
    ]


def get_doc_path():
    return "doc_classes"
