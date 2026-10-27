#include "material_library.hpp"
#include <miniz.h>
#include <chrono>
#include <fstream>
#include <iostream>
#include <stdexcept>
namespace fs=std::filesystem;
namespace mat=rimes::practice::materials;
void Check(bool ok,const char* message) {if(!ok)throw std::runtime_error(message);}
template<class F> void Reject(F function,const char* message) {bool rejected=false;try{function();}catch(const std::exception&){rejected=true;}Check(rejected,message);}
void Archive(const fs::path& path,bool unsafe=false) {
    mz_zip_archive zip{};Check(mz_zip_writer_init_heap(&zip,0,0)!=0,"zip init");
    auto add=[&](const std::string& name,const std::string& text){Check(mz_zip_writer_add_mem(&zip,name.c_str(),text.data(),text.size(),0)!=0,"zip fixture");};
    add("META-INF/container.xml","<container><rootfiles><rootfile full-path='OPS/content.opf'/></rootfiles></container>");
    add("OPS/content.opf","<package><metadata><dc:title>跟打测试</dc:title><dc:creator>测试作者</dc:creator></metadata><manifest><item id='b' href='chapter%20one.xhtml' media-type='application/xhtml+xml'/></manifest><spine><itemref idref='b'/></spine></package>");
    add("OPS/chapter one.xhtml","<html><head><title>不进入正文</title></head><body><h1>第一章</h1><p>清晨的街道已经醒来，早餐店的灯光映在窗上，大家开始了普通而温暖的一天。</p><script>never execute or include this</script><p>路边的小树迎着微风轻轻摇动，天空逐渐明亮起来，鸟鸣从远处传到窗前。</p></body></html>");
    if(unsafe)add("../outside.txt","must not escape");
    void* bytes=nullptr;size_t length=0;Check(mz_zip_writer_finalize_heap_archive(&zip,&bytes,&length)!=0,"zip finalize");
    std::ofstream file(path,std::ios::binary);file.write(static_cast<const char*>(bytes),static_cast<std::streamsize>(length));file.close();mz_free(bytes);mz_zip_writer_end(&zip);
}
int main() {
    auto root=fs::temp_directory_path()/fs::u8path("xsime-material-"+std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()));
    try {
        fs::create_directories(root);const auto epub=root/fs::u8path("书籍.epub");Archive(epub);
        auto book=mat::ParseEPUB(epub);Check(book.at("title")=="跟打测试" && book.at("author")=="测试作者","OPF metadata");
        auto articles=mat::Articles(book);Check(articles.size()==1,"short chapter remains one passage");
        const auto display=articles.front().at("displayText").get<std::string>();
        Check(display.find('\n')!=std::string::npos && display.find("never execute")==std::string::npos && display.find("第一章")==std::string::npos,"paragraphs retained; script and heading not scored");
        Check(articles.front().at("text").get<std::string>().find('\n')==std::string::npos,"paragraph breaks are not typed characters");
        auto rows=mat::TrackRows("天地玄黄\nabc👋",6);Check(rows.size()==2 && rows[0].length==4 && rows[1].start==4 && rows[1].indent==2,"source rows retain scoring offsets and paragraph indentation");
        Check(mat::Characters("e\xcc\x81👨‍👩‍👧‍👦").size()==2,"graphemes, not UTF-8 bytes or surrogate halves");
        mat::Library library(root);Check(library.Books().empty(),"empty library");
        auto saved=library.Import(epub);Check(library.Books().size()==1,"import persisted");
        Check(library.Import(epub).at("id")==saved.at("id") && library.Books().size()==1,"same file replaces by stable identity");
        std::ofstream(root/"unrelated-history.json")<<"preserve";
        library.Remove(saved.at("id"));Check(library.Books().empty() && fs::exists(root/"unrelated-history.json"),"removing a book preserves history and unrelated data");
        Archive(root/"unsafe.epub",true);Reject([&]{mat::ParseEPUB(root/"unsafe.epub");},"archive traversal must be rejected");
        Reject([&]{library.Remove("../unrelated-history");},"book removal accepts only stable book IDs");
        fs::remove_all(root);std::cout<<"Typing material import, storage, Unicode and track rows OK\n";return 0;
    } catch(const std::exception& error) {std::cerr<<error.what()<<'\n';std::error_code ignored;fs::remove_all(root,ignored);return 1;}
}
